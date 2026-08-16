# Native notes

Teaching notes for the two native halves of this project: the WidgetKit extension in
`ios/SimplePhoneWidget/`, and the local Expo module in `modules/launcher-native/`.

The audience is someone comfortable with TypeScript who has not written iOS code recently, or an
agent that needs to change one of these files without breaking the other. The README covers *what
the contracts are*. This file covers *why the native code is shaped the way it is*.

---

# Part 1: WidgetKit

## The mental model

The wrong model, and the one every web developer starts with: "the widget is a small view of my app
that stays on screen and updates."

The right model: **the widget is a slideshow your app pre-renders, and the system decides when to
advance it.**

Your extension process is not alive while the widget is on screen. The system wakes it, asks a
question, gets an answer, and kills it. What sits on the home screen is an archived view tree that
the system can re-lay-out and re-tint without you. Battery is the reason. A hundred widgets running
code all day would end the device.

Three consequences follow, and everything else in this section is downstream of them:

1. **You cannot push an update.** You can only ask the system to throw away what it has and ask you
   again (`WidgetCenter.shared.reloadAllTimelines()`).
2. **You have no persistent state.** Every wake-up starts from nothing. Anything the widget knows,
   it read from disk during that wake-up.
3. **You have a few seconds.** Not enough for a network request you did not plan for, and nowhere
   near enough to boot a JavaScript engine.

## `TimelineProvider` and `TimelineEntry`

A `TimelineEntry` is one frame of the slideshow: a date, plus whatever data your view needs to
render at that date. Ours is trivial:

```swift
// ios/SimplePhoneWidget/LauncherEntry.swift
struct LauncherEntry: TimelineEntry {
    let date: Date
    let apps: [LauncherApp]
    let theme: Theme
}
```

A `TimelineProvider` is the object the system asks for those frames. It has exactly three methods,
each answering a different question:

| Method          | The system is asking                                            | Must be         |
| --------------- | --------------------------------------------------------------- | --------------- |
| `placeholder`   | "Draw something instantly, right now, I need a shape."           | Synchronous     |
| `getSnapshot`   | "Draw one representative frame for the gallery or a transition." | Fast            |
| `getTimeline`   | "Give me the frames and tell me when to come back."              | Can do real work|

### Why `placeholder` uses defaults and `getSnapshot` reads disk

This asymmetry in `ios/SimplePhoneWidget/LauncherProvider.swift` looks like a bug and is not:

```swift
func placeholder(in context: Context) -> LauncherEntry {
    let config = LauncherConfig.default          // bundled defaults, no disk read
    return LauncherEntry(date: Date(), apps: config.apps, theme: config.theme)
}

func getSnapshot(in context: Context, completion: @escaping (LauncherEntry) -> Void) {
    completion(makeEntry())                      // ConfigStore.load(), reads the App Group
}
```

`placeholder` runs in three situations where reading the user's data is either impossible or wrong:

- **It must be synchronous.** There is no completion handler in the signature. It returns a value
  directly. Anything slow blocks the UI that is trying to draw your widget's outline.
- **It must be non-empty.** The system uses it to size and shape the redacted skeleton shown while
  the widget loads. An empty list produces a collapsed, wrong-looking placeholder.
- **It must not show user data.** The same placeholder is rendered in contexts where the user's
  private content should not appear, and it may be rendered redacted, where real names would leak
  through the shape of the layout.

`getSnapshot` has none of those constraints. It gets a completion handler, so it can take its time,
and it is meant to be representative, so real data is correct there.

**Do not "clean this up" into a single `makeEntry()` used by all three methods.** That is the most
tempting refactor in the file and it is wrong in both directions: `placeholder` would start reading
disk synchronously, and it would show user data where it should not.

## Why `policy: .never` is correct here, and only here

```swift
completion(Timeline(entries: [makeEntry()], policy: .never))
```

One entry, and a reload policy that means "do not come back on your own, ever."

This widget shows a list of app names. Nothing about it changes with time. There is no countdown, no
next-event, no stock price. A time-based refresh policy would burn the system's refresh budget to
re-render identical pixels.

**`.never` is correct only because something else triggers the reload.** `ConfigStore.save()` ends
with:

```swift
WidgetCenter.shared.reloadAllTimelines()
```

and the React Native side calls the same thing through `LauncherNative.reloadWidget()` after every
single write. **Those two halves must be ported together.** Drop the reload call and the widget
freezes at whatever it last rendered, permanently, with no error and no way for the user to force a
refresh short of removing and re-adding the widget.

### The reload budget

`reloadAllTimelines()` is a request, not a command. The system allocates a widget roughly **40 to 70
refreshes per day**, and the exact number depends on how often the user looks at the widget, battery
state, Low Power Mode, and how well-behaved the extension has been. Exceed it and your reload
requests are quietly dropped or deferred, sometimes for hours.

For this app that budget is generous. A user who edits their launcher 40 times in a day is doing
something unusual. But it is a real ceiling, and it is why the Appearance screen's segmented control
commits on **discrete tap** rather than continuous drag: a slider that fired a reload per frame
would exhaust the day's budget in about two seconds, and then the widget would stop reflecting
changes for everyone including the user who was not dragging anything.

## `containerBackground(for: .widget)` is mandatory on iOS 17+

```swift
content.containerBackground(for: .widget) { theme.backgroundColor }
```

Before iOS 17, a widget painted its own background however it liked. Since iOS 17 (and this is
enforced, not advisory), a widget must declare its background through this modifier so the system
can remove or replace it: on the iPad Lock Screen, in StandBy, on the desktop in macOS, and anywhere
else Apple decides a widget should be tinted or de-chromed.

If you drop it, the widget does not fail to build. It renders **letterboxed inside a default system
background**, and the theme's dark/light choice, the entire point of this app's Appearance screen,
disappears. It looks like a layout bug and it is a missing modifier.

## What `contentMarginsDisabled()` actually does

Since iOS 17 the system applies default content margins to every widget, roughly 16 points on each
side, so that third-party widgets line up with Apple's. `contentMarginsDisabled()` turns that off
and gives you the full surface.

This widget disables them, which means the bare `.padding()` inside `WidgetViews.swift` is the
**only** inset in the entire layout. That makes the two modifiers a matched pair:

- Drop `contentMarginsDisabled()` and the padding doubles. Large text gets cramped and the row limits
  (1 / 3 / 6) stop fitting.
- Drop the `.padding()` and text touches the widget edge.

Both are one-line changes and both look like harmless cleanup. They are not.

## The `kind` string must never change

```swift
StaticConfiguration(kind: "SimplePhoneLauncher", provider: LauncherProvider()) { ... }
```

`kind` is the widget's identity as far as the system is concerned. When a user drags your widget
onto their home screen, iOS persists that string in its own database and uses it forever after to
ask *which* widget it should be rendering.

Rename it and every already-placed widget on every device goes blank or unconfigured. The user has
to notice, delete it, and add it back. There is no migration API and no way to alias an old kind to
a new one.

`"SimplePhoneLauncher"` is inherited from the original Swift app, so widgets placed from that app
keep working after installing this port. It is a permanent string. Treat it like a database column
name in production.

## Row limits and the family switch

```swift
switch family {
case .systemSmall:  smallView            // apps.first only
case .systemLarge:  listView(limit: 6)
default:            listView(limit: 3)   // systemMedium, and anything else
}
```

The limits 1 / 3 / 6 are hard-coded and do **not** react to the theme's text size. At `extraLarge`
(44pt widget font), six rows on `systemLarge` only fit because `LauncherRowLabel` applies
`minimumScaleFactor(0.5)` and lets long names shrink rather than truncate. Any change to the VStack
spacing (16), the padding, the font sizes, or `fontWeight(.semibold)` shifts what actually fits.
Re-check `systemLarge` at `extraLarge` with long app names after touching any of them.

Also note that `default:` serves `systemMedium`. If you add `.accessoryRectangular` or
`.systemExtraLarge` to `supportedFamilies` without extending the switch, those families silently
render the 3-row layout at widget font sizes, which overflows badly on a Lock Screen accessory.

## No `NSExtensionPrincipalClass`

`ios/SimplePhoneWidget/Info.plist` declares only:

```xml
<key>NSExtension</key>
<dict>
  <key>NSExtensionPointIdentifier</key>
  <string>com.apple.widgetkit-extension</string>
</dict>
```

That is correct and complete for a SwiftUI extension whose entry point is `@main struct
SimplePhoneWidgetBundle: WidgetBundle`. The `@main` attribute generates the entry point at compile
time.

Older Objective-C widget templates declare `NSExtensionPrincipalClass`, and copying that habit into
a SwiftUI widget breaks the extension at launch, because the system then tries to instantiate a
class that does not exist. Same for a storyboard key. Do not add either.

---

# Part 2: Expo Modules

## What a local Expo module actually is

`modules/launcher-native/` is a **local Expo module**: a small native library that lives in your
project rather than in `node_modules`, and that Expo's autolinking picks up automatically.

It is not a config plugin (those modify the Xcode project at prebuild time, which this project never runs, and run no
device code). It is not the old React Native bridge module either, with its `RCT_EXPORT_METHOD`
macros and its NSDictionary marshalling. It is a Swift class that declares its JS-facing API in a
DSL:

```swift
public class LauncherNativeModule: Module {
  public func definition() -> ModuleDefinition {
    Name("LauncherNative")

    Constants(["appGroupId": "group.com.guilherme44.simple-phone"])

    Function("readConfigJSON") { () -> String? in ... }
  }
}
```

`definition()` is not executed like normal imperative code. It builds a description of the module
that Expo's runtime reads to wire up the JS side. Argument types are inferred from the Swift closure
signature and validated at the boundary, which is why there is no manual type-checking or unwrapping
in the module body.

### The three files, and what each one is for

```
modules/launcher-native/
  expo-module.config.json         tells autolinking this module exists
  index.ts                        the typed TypeScript facade
  ios/
    LauncherNative.podspec        tells CocoaPods how to compile the Swift
    LauncherNativeModule.swift    the actual code
```

**`expo-module.config.json`** is the entry point for the whole mechanism:

```json
{ "platforms": ["apple"], "apple": { "modules": ["LauncherNativeModule"] } }
```

During `pod install`, `expo-modules-autolinking` scans `node_modules` **and the local `modules/` directory**
for this file. Every module it finds gets added to the generated Podfile and registered with the
runtime. The `modules` array names the Swift **class**, and the name must match exactly, because
that is the string the generated registration code uses.

**The podspec** is ordinary CocoaPods: name, platform floor (`ios, '17.0'`, matching the widget),
`dependency 'ExpoModulesCore'`, and `source_files`. Nothing Expo-specific. It exists because the
generated Podfile needs a pod to point at.

**`index.ts`** is the only file the rest of the app imports:

```ts
import { requireNativeModule } from 'expo';
const LauncherNative = requireNativeModule<LauncherNativeModule>('LauncherNative');
```

`requireNativeModule` looks the module up **by the string passed to `Name(...)` in Swift**, not by
the class name and not by the folder name. It returns the installed host object, and it throws
immediately if the module is missing rather than handing back `undefined` for you to trip over
later. Three different names are in play (folder, class, `Name(...)`) and only the last one is the
lookup key.

Wrapping it in a typed interface in `index.ts` is the only place TypeScript gets to know these
functions exist. The native side cannot generate types for you.

## `Function` vs `AsyncFunction`, and why it matters here

This is the single most important thing to understand about the Expo Modules API, and it is one word
of difference in the source.

**`AsyncFunction`** returns a `Promise` in JavaScript. The work is dispatched to a module queue, off
the JS thread, and the result is delivered back later. This is the safe default and the right choice
for anything that can be slow: network, file I/O, image processing, database work.

**`Function`** is **synchronous over JSI**. There is no Promise, no queue hop, no serialization
round trip. JSI (JavaScript Interface) lets native code install real C++-backed host objects
directly into the JS runtime's global scope, so calling one is a direct function call into native
code on the JS thread, the way `Math.max` is:

```ts
const json = LauncherNative.readConfigJSON();  // a string, right now, not a Promise
```

The old React Native bridge could not do this at all. Every call was asynchronous message-passing
over a serialized queue. JSI is what removed that constraint, and it is the core of the New
Architecture (mandatory since SDK 55, so it is simply how things work now).

### Why all four functions here are synchronous

`readConfigJSON`, `writeConfigJSON`, `reloadWidget` and `resolvedFontFamily` are all declared with
`Function`. That is deliberate, and it buys one specific thing.

The original Swift app's `LauncherStore.init` called `ConfigStore.load()` synchronously. By the time
the first view rendered, the config existed. There was no loading state, because there was no moment
at which the config was unknown.

Synchronous `Function` reproduces that exactly:

```ts
const [config] = useState(() => loadConfig());   // lazy initializer, runs during first render
```

No `useEffect`, no `loading` boolean, no splash screen held open, no flash of an empty list before
the apps appear. The store is correct on the first frame.

The cost is that these calls block the JS thread. That is acceptable **only** because of what they
do: a `UserDefaults` read of a few kilobytes, backed by an in-memory cache that iOS has usually
already faulted in. Sub-millisecond. If any of these ever grew to touch the network, decode an
image, or scan a directory, it would need to become an `AsyncFunction`, and the store would need a
loading state, and this whole paragraph would stop being true.

**Rule of thumb:** `Function` for cheap, bounded, local work where synchronicity buys you a simpler
architecture. `AsyncFunction` for everything else. When in doubt, `AsyncFunction`.

## Why this module exists at all

`@bacons/apple-targets` ships an `ExtensionStorage` module that almost does this job (it was
evaluated while this project was still on CNG). Three reasons
we do not use it, all of them worth understanding:

1. **`setObject` round-trips through `JSONSerialization`,** which can coerce a JS boolean to `1`.
   The full failure chain is in the README, and it ends with the user's entire app list silently
   reset to defaults. This project passes a `String` across the boundary so that JavaScript owns the
   exact bytes and nothing in the middle gets an opinion about them.
2. **It cannot read the legacy `Data` value** the old Swift app wrote under `launcher_config`, which
   is what makes the in-place upgrade work.
3. **It has no font resolver.** React Native cannot express SwiftUI's `Font.Design`, so
   `resolvedFontFamily` uses `UIFontDescriptor.withDesign(.rounded / .serif / .monospaced)`, the
   public API that turns a design into a concrete family name RN can put in a `fontFamily` style.
   Without it, the in-app widget preview renders in different typefaces than the real widget, which
   defeats the point of having a preview.

## App Groups from the native side

An App Group is a **shared container**: a `UserDefaults` suite plus a shared filesystem directory
that multiple binaries signed by the same team can both open, provided each one carries the
`com.apple.security.application-groups` entitlement naming that group.

```swift
let defaults = UserDefaults(suiteName: "group.com.guilherme44.simple-phone") ?? .standard
```

Two things about that line are worth internalizing:

**The initializer returns an optional, and `nil` is not an error you can inspect.** It fails when the
suite name is malformed, or the process is not entitled to that group. You get `nil`. No `Error`, no
`errno`, no log. That is why the fallback exists and why the failure is undetectable from inside the
process, as described in the README.

**Entitlements are a signing-time fact, not a runtime one.** The entitlement is baked into the
signature by the provisioning profile. You cannot check for it, request it, or repair it at runtime.
If the build was signed without it, the running binary simply cannot see the container, forever.
This is the shape of most iOS capability failures: things degrade to silence rather than erroring,
because the entitlement is verified before your code ever runs.

Also worth knowing: `UserDefaults` is not a database. It is a plist that gets loaded into memory
whole and written back whole, and it is intended for small values. One JSON config of a few
kilobytes is exactly the intended use. A list of thousands of apps with per-app images would not be,
and would want the shared *directory* half of the App Group instead.

---

# Part 3: Bare vs CNG, in 2026

The terminology here is old and half of what you will find online is stale. Here is the current
state.

**"Bare workflow"** used to mean: you have `ios/` and `android/` directories committed to your repo,
you open Xcode, you edit things there, and you own them from then on. The opposite was the "managed
workflow", where you never saw native code at all and were limited to whatever Expo Go supported.

**That dichotomy is gone.** It has not been how Expo works for several SDK cycles. What replaced it
is **CNG: Continuous Native Generation.**

CNG means the native projects are **build artifacts derived from a declarative spec**, exactly the
way `node_modules` is derived from `package.json`:

```
app.json  +  config plugins  +  targets/  +  modules/
                       |
              npx expo prebuild
                       |
                       v
                  ios/  (disposable)
```

The real question is not "managed or bare". It is whether `ios/` is **input** or **output**.

**This project treats `ios/` as input.** It is committed source, hand-edited in Xcode, and
`npx expo prebuild` is forbidden here because it would regenerate and destroy it.

That is a deliberate reversal of the Expo default, made for two reasons:

1. **Learning.** Under CNG the Xcode project is a black box a plugin rebuilds. You learn the
   plugin's config schema, not Xcode. Owning `ios/` means you can open the project, see both
   targets, see the embed phase that puts `SimplePhoneWidget.appex` inside `SimplePhone.app`, and
   change any of it directly.
2. **Fewer moving parts.** Getting a hand-written Swift extension into a CNG project requires
   `@bacons/apple-targets`, a single-maintainer package whose pbxproj writer is still an alpha. This
   project used it once to generate the target, then removed it. What it produced is now ordinary
   committed project state that nothing regenerates.

### What you give up

Be honest about the trade, because it is real:

| Under CNG                                  | Under bare (here)                             |
| ------------------------------------------ | --------------------------------------------- |
| `app.json` drives icon, splash, plist       | Xcode drives them; `app.json` is inert for those |
| SDK upgrade: regenerate and move on         | SDK upgrade: hand-merge native changes        |
| `.pbxproj` never conflicts in git           | `.pbxproj` can and will conflict              |
| Adding a plugin "just works"                | A plugin that patches native code does nothing |

That last row is the one that bites. A config plugin only runs during prebuild. **Installing an npm
package whose install instructions say "add this plugin to app.json" will not work here** — you have
to read what the plugin does to the native project and apply it in Xcode yourself.

### Where custom native code goes here

| What you need                         | Where it goes                | Mechanism                     |
| ------------------------------------- | ---------------------------- | ----------------------------- |
| A native module callable from JS      | `modules/<name>/`            | local Expo module, autolinked |
| An app extension (widget, share, ...) | `ios/<TargetName>/`          | a target you add in Xcode     |
| Xcode project or plist changes        | `ios/`                       | Xcode                         |

Local Expo modules still work exactly as before: `expo-modules-autolinking` scans `modules/` during
`pod install`, so `modules/launcher-native/` is picked up with no prebuild involved. That is why the
bridge survived the conversion untouched.

### One caveat worth knowing

Some settings live in files that prebuild used to own. For example, the SDK 57 escape hatch for the
Hermes V1 memory regression (Hermes V1 plus `react-native-reanimated` raises memory usage 25 to 30
percent even when Reanimated is idle) is:

```json
// ios/Podfile.properties.json
{ "expo.useHermesV1": "false" }
```

Under CNG that edit would be erased by the next prebuild and would need a config plugin to persist.
Here it is simply a committed file you edit and keep. This is the upside of bare: the escape hatch
is a one-line change instead of a plugin.

---

# Part 4: The relay cover

A widget row cannot open a third party app. The tap lands here, a full-screen
cover carries a phrase, and the app forwards you on. Everything below is what
that round trip actually costs on a device, and none of it is visible in a
simulator, which refuses third-party schemes.

Read `RelayGate.swift` and `RelayReturn.swift` alongside this. They hold the
rules; this holds the reasons.

## The dead 420 milliseconds

**iOS delivers no touch to this app for roughly the first 420ms of a widget
tap.** Measured, not guessed. A trace of eleven real taps on an iPhone 17 Pro
running iOS 26.6:

| Moment | When |
| --- | --- |
| `application(_:open:)` runs | 0 |
| `didBecomeActive` | 0.21 to 0.23 |
| earliest touch the app ever saw | 0.42 |

Never once earlier, and not on the host window either, which listens precisely
to catch that case. For that first stretch the finger belongs to the home
screen and the system does not hand it over.

Two consequences shaped the whole feature.

**A duration counted from the relay is partly spent on a picture.** The phrase
is visible from 0 because iOS is replaying the snapshot taken at the last
backgrounding, so a "1.5 second" cover used to offer 1.36 seconds you could
touch and 0.4 you could only look at. The countdown now starts after
`touchSettleDelay`, so the number in the Phrases screen means what it says.

**A press on reflex cannot work, and no API can see it.** So the app answers the
press it did get, immediately and in two ways: a light haptic and the badge
freezing. A press that does not buzz is a press that never arrived. Lift, press
again. That is the fact rather than a description of it, which is worth more
than any hint text.

## A countdown that cannot lie

The badge at the top of the cover shows how long the phrase has left, and its
countdown **starts when the app can be touched, not when the relay began.**

Starting it at zero was the obvious thing and it is not possible. For that first
stretch the app is not drawing at all: the screen is a still snapshot the system
took before the app left, and a still frame cannot count. Anything animated
there is frozen at whatever value it was painted with and then jumps.

So the start line moves instead. The timer already started at
`didBecomeActive + touchSettleDelay` for the reason above, and the ring now
starts there too. The two agree, nothing jumps, and the price is that the phrase
is on screen for a few hundred milliseconds longer than the ring claims. Nobody
notices 300ms on a phrase. Everybody notices a counter that jumps.

The alignment then pays for itself twice, because it makes the dead window
legible without a word of explanation: **a ring that is moving is a cover that
can be caught.** Before it moves, nothing is reachable and nothing is counting,
so there is nothing on screen making a promise the platform will not keep.

Both boundaries sweep **clockwise**, and draining is the natural place to get
that wrong. Animating `strokeEnd` down from whole retracts the arc's leading edge
anticlockwise, which against a pin that fills clockwise reads as two unrelated
animations arguing with each other. `strokeStart` up from nothing eats the ring
away from the same end the pin grows from, so the second gesture looks like it
continues the first.

## Hold to read, drag to keep

The pin is driven by DISTANCE, not by time. Resting a finger pauses the cover,
for as long as you like, and commits to nothing. Dragging closes the pin ring in
proportion to how far the finger has travelled; coming back toward where it
started opens it again; whole means pinned.

**Held and pinned are not the same suspension.** A cover that was pinned already
carries the pin's controls and the drag that leaves it, and comes back needing
only its gate locked again. One that was merely HELD carries none of that, and
locking it produced a full-screen phrase with no countdown, no controls and no
working gesture, surviving a relaunch — the worst failure this code can have,
reintroduced through the newest path into it. A held cover therefore comes back
through the same code that builds a pin from scratch.

The pin's controls are tagged so they can be taken off as a group, and
`clearCoverGestures` does exactly that. A pinned cover walked away from is left
standing on purpose, and the next warm relay reuses whatever cover it finds:
without stripping them the launch inherited that pin's Copy, Share and "Open The
Simple Phone", and the last of those silently cancels the relay the user just
asked for.

It was a 1.2 second hold first, and the reason it changed is the dead window
above. A timed hold asks the user to commit before they know whether they were
heard: a press that never arrived cost them the entire wait before anything told
them so. A drag answers in the first millimetre, because the ring is following
the thumb rather than a clock.

It also separates two intentions that a timeout had to guess between. Wanting to
finish reading and wanting to keep the line are different things, and neither is
now a timeout on the other.

The travel is measured from where the finger was first **seen**, not from where
it landed — on a warm relay those are not the same point, since the first
stretch of the touch belonged to the home screen. Seen is the honest baseline
and it is the one the user's eye agrees with, because the ring starts moving
from that same instant.

### The whole of the gesture

A finger down on the cover can end in exactly four ways, and only one of them
needs anything more than lifting.

| What the finger does | Glyph | Ring | On lifting |
| --- | --- | --- | --- |
| Rests, or moves under 8pt | pause | at nothing | the countdown resumes where it stopped |
| Drags **down** under 120pt | pause | part closed | the countdown resumes where it stopped |
| Drags **down** past 120pt | pause | closed, one buzz | the cover is pinned |
| Drags **sideways** under 60pt | forward | part closed | the countdown resumes where it stopped |
| Drags **sideways** past 60pt | forward | closed, one buzz | goes to the app |
| Is cancelled by the system | — | — | the countdown resumes, WHATEVER the ring said |

That last row is a decision, not a fallthrough. A call arriving or a system
gesture claiming the touch is not the user deciding, so a closed ring is thrown
away rather than honoured: acting on it pinned the cover, or launched the app,
on an interruption they had no part in.

**Nothing acts while the finger is down.** Closing a ring is a promise about
what lifting will do and nothing more, which is what makes both gestures
retractable: drag back, the ring opens, the buzz is taken back, the finger is
free again.

Pinning used to fire the moment its ring completed, on the reasoning that the
finger stops mattering once the cover is staying. It read as the gesture going
off in the user's hand — the cover pinned itself and its controls appeared under
a thumb that was still moving, with no way back short of the exits. The two
gestures also stopped rhyming, and one of them having a different relationship
with the finger than the other is the kind of thing a hand notices before a head
can name it.

**One gesture at a time**, decided by whichever axis has travelled further, and
the ring and the glyph always agree because the same answer picks both. Switching
axes mid-drag hands both over: a sideways drag that turns downward becomes a pin
in progress, and the arrow becomes a pause again.

Letting the two run side by side is what put a forward arrow on a cover that had
just been pinned. The ring answered the drag down while the glyph still answered
the drag sideways, and neither was wrong on its own — which is the tell that the
model was missing, not the drawing.

**8 points of slack** before either axis owns anything. Below that a resting
thumb's own tremor decides which is larger, and the glyph flickers between pause
and forward on a hand that is holding still.

**Sixty points against a hundred and twenty**, because they ask for different
things. Skipping ahead only brings forward what the cover was going to do on its
own; pinning takes the launch away entirely and should cost more than a flinch.

### Leaving a cover that is already pinned

The same gesture, the same glyph, the same ring, the same sixty points. **The way
out has the shape of the way in**, which is the only reason anyone would guess it
exists. The rings were retired when the cover pinned, so the drag brings them
back, and a drag that stops short puts the pinned look straight back.

There used to be a tap here as well and it is gone. It was the one way out of
this cover that cost nothing, on a cover that exists *because* the user
deliberately stopped the screen from moving, so a stray thumb undid the very
thing they had asked for. It was also the only gesture on the whole cover that
acted with no ring behind it. The button at the bottom is still there for
anyone who would rather aim at a target than drag.

The exit's armed flag is its own rather than the hold's, because
`CoverView.touchesEnded` calls `forgetHold` on a pinned cover too and UIKit gives
no order between that callback and a recogniser's `.ended`. Sharing one flag made
the exit work or not depending on which arrived first.

### Down only, and what makes that survivable

Coming back up unwinds the pin ring rather than closing it from the other side,
which is what makes backing out feel like backing out.

That leaves the bottom 120pt of the screen unable to reach the threshold, because
the glass runs out before the distance does, and that band is exactly where a
thumb rests when the phone is held in one hand.

It is survivable only because **lifting no longer hands off**. A thumb that
landed too low presses again higher up and loses nothing: the countdown simply
carries on. Under the earlier rule, where a press marked the relay due, the same
finger cost the user their launch — one attempt per relay, its success decided by
where the thumb happened to land, with the ring answering the drag, stalling part
closed, and reading as a broken app. The fix at the time was to accept an upward
drag as well. Making a press mean nothing on its own replaced it.

The travel belongs to **one** finger, named by its `UITouch`. `UIEvent` delivers
touches in an unordered `Set`, so without an identity a second finger resting on
the glass has its position measured against the first finger's origin: the
distance between two thumbs, read as a drag nobody made, pinning the cover with
no travel at all. For the same reason a lift is only a lift when it is the last
one — letting go of the passenger used to wipe the origin and unwind the ring
under a thumb that had not moved.

A **pause** sits at the centre once a finger is down, and stays after the pin.
Not a padlock: a padlock says you cannot leave, which is false, since a tap, a
drag sideways and the button all still work. A pause says nothing happens until
you say so, which is what is actually true, and it is the same word the frozen
ring is already saying.

A padlock glyph inside a ring failed twice before this, both times drawn into a
bare `CALayer` positioned under the finger. The pause renders because the badge
is an ordinary `UIView` at a fixed place in the hierarchy, with the glyph in a
`UIImageView` (see "SF Symbols in a UIImageView" below for the other half of
why).

## Touches on the cover

The cover is its own `UIWindow` above everything, and touches reach it three
different ways depending on when the finger lands.

**`CoverView.touchesBegan`** is the ordinary case.

**`CoverView.touchesMoved`** is the finger that landed during the app-switch
animation. It produces no `touchesBegan` here, having begun while the home
screen still owned it, and surfaces only once it moves.

**`CoverWindow.sendEvent`** is the same finger when it does not move at all.
`UIEvent.allTouches` carries touches in the `.stationary` phase, which produce
no view callbacks whatsoever. Without this the stationary-finger case could hold
the cover but never freeze the badge, so it could never pin anything.

There is a fourth listener, on the app's **own** window rather than the cover's:
a zero-duration `UILongPressGestureRecognizer` for the stretch where the overlay
is being drawn but is not necessarily the window UIKit routes the touch to.

### Every route must say both halves

All four speak to two pieces of state, the gate and the badge, and **a route
that tells one and not the other is a bug every time.** Two of them shipped that
way and both were caught in review rather than on the device.

`sendEvent` called `fingerLanded` on the way down and only `gate.release` on the
way up, and the host-window recogniser spoke to the gate alone. The failures do
not look alike, which is the point: the first strands a hold flag set forever,
so the badge and the pin quietly stop working for the life of the process; the
second lets the ring drain past zero while the handoff is held back, a cover
sitting still with nothing on screen admitting why.

The state has no owner that can enforce this, so the rule has to be read. If you
add a touch route, it says both halves or it says nothing.

### Recognisers cancel touches, and the window outlives the relay

The cover's window is only torn down when the user comes back with nothing
pending, so it survives many relays. Every pin and every return card used to
add another gesture recogniser to the same view, and a `UIPanGestureRecognizer`
among them **cancels the touches the view is using** as soon as it starts
recognising. A thumb's natural drift was enough: the ring vanished and the
target opened.

Holding therefore degraded the more the feature was used, which is the shape of
a leak rather than a bug in the hold. Two fixes, and either alone hides the
other:

- `clearCoverGestures()` when a relay begins.
- `cancelsTouchesInView = false` on every recogniser added here.

## One paint, two audiences

The hardest problem in this file, and the one worth understanding before
changing anything about rolling.

The cover painted on the way out has to serve **two** later moments:

1. **A return.** The user taps the `TSP` breadcrumb, and the card shows the line
   they missed. iOS replays the exit's snapshot during the whole animation.
2. **The next launch.** A warm relay keeps whatever is painted rather than
   re-drawing, which is what stops the text swapping mid-transition.

These want opposite things, and both naive answers are wrong:

- **Roll on the way out** and the snapshot carries a line the card then
  corrects. The user watches the phrase change under them on the way back.
- **Do not roll** and the line never changes. Worse, and older: the pending
  return that would gate the skip is only consumed by opening the app, and
  somebody who only ever taps the widget never opens it.

The question is neither. It is **"was the last card ever collected?"** A card
still owed when a new relay starts means the user went back to the home screen
and launched something else instead of tapping the breadcrumb: that line is one
they chose not to read, and the next exit is free to roll.

So an exit ending a relay someone may still return to keeps its line, and the
exit after one they walked away from rolls. A line repeats at most once, and
only to the person who ignored it.

**A cold relay counts as uncollected.** `pendingReturn` is memory-only, so a
process killed between relays takes the evidence with it. Without treating cold
as proof, the exit always found a fresh pending return, always kept the line,
and the next cold relay restored the very same one: the phrase froze for good.
Cold is the *ordinary* case for a launcher, since iOS reclaims it while you are
in the app it launched.

### Rolling and counting are not the same act

They used to be one call, which is why every arrangement above broke something:
keeping a phrase for the card meant not counting it.

- `roll` picks and paints. It runs on a backgrounding, and what it paints may be
  replaced by a card or never foregrounded at all.
- `countAsShown` scores, on the relay that actually puts the line in front of
  somebody.

This also retires an inaccuracy the code used to admit to: the app-switcher card
and a plain icon launch raise the cover without anyone launching anything, and
used to score for it.

## SF Symbols in a UIImageView

`UIImageView` honours `tintColor` **only for a template image**, and
`UIImage(systemName:)` returns `.automatic`, which a plain image view renders in
the symbol's own colour: black. A black padlock on a black cover is invisible,
and the pin looked broken when the only thing missing was its colour.

`UIButton` resolves this itself, which is why Copy and Share appeared and the
padlock did not. Colour it into the image instead:

```swift
UIImage(systemName: "lock.fill", withConfiguration: config)?
  .withTintColor(colour, renderingMode: .alwaysOriginal)
```

## The worst failure this code can have

A launcher that never launches. It is worth naming because two separate bugs
have reached it, and both looked harmless in isolation.

A pinned cover the user walks away from used to leave the pin set: `endRelay`
only drops `relayInFlight`, and `dismiss` refuses to run while a relay is in
flight, so nothing unlocked. The next tap then armed behind a pin with no ring,
no controls and no gestures left on screen. Neither the pin nor
`clearCoverGestures` was wrong alone; together they closed the last door.

`arm()` therefore clears the pin and the finger with it. `isHeld` is otherwise
preserved across arming, because a press can legitimately land before the relay
is armed, but a press still down when the cover was pinned belongs to that
cover: nobody holds a phone through someone else's launch.

## Testing the native half

The app target has no XCTest bundle, and adding one means surgery on a committed
`pbxproj`. So `scripts/test-relay-gate` compiles the real files against
`scripts/relay-gate-tests.swift` and runs the cases:

```bash
./scripts/test-relay-gate
```

`npm test` does **not** run it. This works only while `RelayGate.swift` and
`RelayReturn.swift` import nothing but Foundation; a single `import UIKit` in
either deletes the native half's only executable test, silently.

Two habits the suite depends on:

- **Time is an argument**, never a wait. `durationElapsed(_:)` and
  `consume(at:)` are called by hand.
- **Prove each case bites.** Run it against the wrong implementation and watch
  it go red. A guard written in two places once left every case green while
  nothing enforced the rule, because each masked the other.
