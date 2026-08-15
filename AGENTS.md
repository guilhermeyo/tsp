# AGENTS.md

Rules for anyone, human or agent, writing code in this repo.

Read `README.md` for what the app is and why it is built this way. Read `docs/native-notes.md`
before touching Swift. This file is the short list of things that will break something if you get
them wrong.

---

## Expo has changed

Do not write Expo code from memory. The API surface has moved substantially and most search results
are stale.

**Read the versioned docs: https://docs.expo.dev/versions/v57.0.0/**

Specifically stale advice to ignore: the old bridge module API with `RCT_EXPORT_METHOD` (replaced by
the Expo Modules API), and anything about `expo eject` (that command no longer exists).

Note that most Expo docs assume CNG, where `ios/` is generated. **This project is bare** — `ios/` is
committed source. See `docs/native-notes.md` part 3 and the README section "This is a bare project".

---

## Repo shape

```
index.js                  the entry point. `main` in package.json points HERE, not at
                          expo-router/entry, so the debug overlay can load first.
app.json                  JS-side config only: scheme, name, build properties.
ios/                      the Xcode project. TWO TARGETS. COMMITTED. SOURCE.
  SimplePhone/            the app target. AppDelegate (the relay), QuoteScreen (the
                          cover), QuoteCatalog (phrases and tallies), RelayGate and
                          RelayReturn (the two pure rules).
  SimplePhoneWidget/      Swift for the WidgetKit extension.
modules/launcher-native/  Swift for the local Expo module.          COMMITTED. SOURCE.
src/                      the React Native app. TypeScript, strict.
scripts/                  the native test runner, and brand asset generation.
docs/                     teaching notes. Part 4 is the relay cover.
```

**`ios/` is source here, not output.** That is the opposite of a default Expo project.

### Never run `expo prebuild`

```bash
npx expo prebuild   # NEVER. Clears and regenerates ios/ by default as of SDK 57.
```

It would delete the committed Xcode project, both targets, and every hand edit, with no prompt. This
project was converted to bare deliberately; prebuild is the one command that undoes it.

`pod install` is fine and expected after any JS dependency change. It rewrites `Pods/` and the
workspace, not `SimplePhone.xcodeproj`.

Changes belong in exactly three places now:

| What you want to change                | Where it goes                        |
| -------------------------------------- | ------------------------------------ |
| Bundle id, entitlements, plist, targets | Xcode, in `ios/`                    |
| Scheme, JS-side Expo config             | `app.json`                          |
| Anything that must run before the app   | `index.js`                          |

`app.json` still lists `ios.bundleIdentifier` and `ios.entitlements`. **Those are inert.** They were
consumed once when the project was generated. Editing them now changes nothing.

### Adding Swift to the widget

`ios/SimplePhoneWidget/` is a `PBXFileSystemSynchronizedRootGroup` (Xcode 16+). Drop a `.swift` file
in and it joins the target automatically, no pbxproj edit required.

### Adding Swift to the APP target is NOT the same

`ios/SimplePhone/` is **not** a synchronized group. A new `.swift` file there is invisible to the
build until it is registered in `project.pbxproj` in four places: `PBXBuildFile`, `PBXFileReference`,
the group's `children`, and the target's `Sources` phase. Mirror an existing entry such as
`RelayGate.swift` and keep the ids unique.

The failure is loud but misleading: `cannot find 'X' in scope` at every call site, as though the type
were never written.

### After renaming the project directory

CocoaPods bakes absolute paths into cached podspecs under `~/Library/Caches/CocoaPods`, and
`pod install` reuses them, so it will happily rewrite the OLD path back into the generated xcconfigs.
Symptoms are unrelated-looking: a missing `React-VFS.yaml`, or `hermesc: No such file or directory`
only in Release, since Debug never bundles. Delete the stale cached specs and reinstall:

```bash
grep -rl "<old-dir-name>" ~/Library/Caches/CocoaPods | xargs rm -f
cd ios && pod install
```

---

## Things that silently destroy user data

Both of these fail with no error, no log, and no crash. They are the reason this file exists.

### 1. Never write config through an object-bridging API

Always `JSON.stringify` a plain object and hand the native side a **string**.

Object bridging coerces the JS boolean `true` to `1`. Swift's
`decodeIfPresent(Bool.self, forKey: .isDark)` then **throws** `typeMismatch` (it returns `nil` only
for absent or null keys). The throw escapes `Theme`'s resilient init, `ConfigStore.load()`'s `try?`
swallows it, and the entire `LauncherConfig` resets to `.default`. Every app the user added is gone.

This is why the local module in `modules/launcher-native/` takes a `String` and never an object, and
why no off-the-shelf key-value bridge is used. Full chain in `README.md`.

### 2. Never rename the widget `kind` string

`"SimplePhoneLauncher"` in `ios/SimplePhoneWidget/LauncherWidget.swift`. WidgetKit persists it for widgets
already placed on home screens. Renaming it blanks every one of them, on every device, permanently.
There is no migration API.

---

## The data contract

Byte-identical, non-negotiable. It is what the old Swift app wrote.

```
App Group:        group.com.guilherme44.simple-phone
UserDefaults key: launcher_config
```

```json
{"apps":[{"id":"<uuid>","name":"...","urlString":"..."}],
 "theme":{"isDark":true,"font":"monospaced","alignment":"center","size":"large"}}
```

Enum values are the lowercase Swift case names verbatim:

- `font`: `monospaced` | `system` | `rounded` | `serif`
- `alignment`: `leading` | `center` | `trailing`
- `size`: `small` | `medium` | `large` | `extraLarge`

Point sizes are two separate tables. Do not mix them:

- Widget and in-app preview: **20 / 28 / 36 / 44**
- In-app list rows: **17 / 22 / 28 / 34**

The App Group id lives in two entitlements plists that must match byte for byte. A stray space fails
signing with a message that does not mention the group:

```bash
plutil -p ios/SimplePhone/SimplePhone.entitlements
plutil -p ios/SimplePhoneWidget/SimplePhoneWidget.entitlements
```

---

## The deep link scheme is `simplephonern`

Not `simplephone`. The old native Swift app owns that one and may still be installed on the same
device. Two apps registering the same scheme means iOS picks a winner arbitrarily.

Widget rows link to `simplephonern://open?u=<encoded target>`. The scheme string lives in FIVE
places that must agree, and only one of them decides whether a tap opens anything:

| Where | Role |
| --- | --- |
| `ios/SimplePhone/AppDelegate.swift`, `Relay.scheme` | **the running parser.** The relay handles the URL natively, before React Native |
| `ios/SimplePhone/Info.plist`, `CFBundleURLTypes` | what the app registers with iOS |
| `ios/SimplePhoneWidget/DeepLink.swift` | what the widget rows link to |
| `app.json`, `expo.scheme` | feeds Expo Router |
| `src/domain/deepLink.ts` | the JS mirror |

`parseTarget` and `DeepLink.target(from:)` currently have no callers: the relay moved into
`AppDelegate` and both parsers stayed behind. The tested parser is therefore NOT the running parser
— a divergence to close before trusting `deepLink.test.ts` as coverage of the relay.

A widget tap can never open a third-party app directly. Never put a third-party scheme in a widget
`Link` or `widgetURL`. See the relay story in `README.md`.

---

## Code rules

- **TypeScript strict.** No `any`, no `@ts-ignore`. `npx tsc --noEmit` must be clean before any
  commit.
- **No emojis anywhere.** Not in code, not in UI strings, not in commits, not in docs.
- **No AI attribution.** No tool credit, no "generated by" banners, no `Co-Authored-By` trailer, and
  no comment explaining that a file was written with assistance. That applies to code, comments and
  commit messages without exception. Prose in `README.md` and `docs/` may discuss AI as a **subject**
  when it is part of the story being told, because how this codebase was built is a real answer to
  why it looks the way it does. Subject, not signature: writing about the process is fine, stamping
  a credit on the output is not.
- **English everywhere.** Code, comments, commits, docs.
- **The bundled default app names are LOCALIZED, not fixed.** They live in
  `src/domain/bundledDefaults.ts` as a name per language per target, and they use the names Apple
  itself uses for those apps in each language, because a launcher row that does not read the way the
  home screen reads has to be translated in the user's head. Switching language renames only a row
  that still carries the OUTGOING language's default; anything the user renamed is theirs and never
  moves. The Swift mirror is English only, and the comment there explains why.
- **Comment WHY, not WHAT.** Obvious TypeScript should not be commented at all. The native files
  carry more, but there is a place for each kind and the code is only one of them:

  | Kind | Where it goes |
  | --- | --- |
  | An invariant that breaks something if ignored | **In the code**, short, at the line that would break it |
  | A platform fact that cost hours to learn | **`docs/native-notes.md`**, with a one-line pointer from the code |
  | A design tension and the option rejected | **`docs/native-notes.md`**, same |
  | What used to be there and why it was wrong | **The commit message**, and nowhere else |

  The last row is the one that inflates files. It is already in `git log`, and repeating it beside
  the code buys nothing while making the code harder to read.

  As a rough gauge, the native files sit around 40 percent comment. Well past that usually means
  narrative has leaked in from the last row.
- The `?? .standard` fallback in `ConfigStore.swift` and `LauncherNativeModule.swift` is
  intentional. Do not remove it. See the App Group story in `README.md`.

### Do not "fix" these

They look like bugs. They are faithful ports of deliberate behavior:

- `placeholder` uses `LauncherConfig.default` while `getSnapshot` uses `ConfigStore.load()`.
- `Timeline(policy: .never)` with no time-based refresh.
- Two rendering paths in `WidgetViews.swift` (`Link` does not work in `systemSmall`).
- Delete has no confirmation, on either of the two delete paths.
- The Appearance screen has no Done button. Every edit commits live; swipe-down is the exit.
- "Choose from catalog" prefills the form only. It never adds or saves anything.
- Empty-state text uses the theme's font family but not the theme's size.
- The list has no separators.
- Returning to a card **after ignoring the previous one** shows the phrase change. One paint cannot
  serve both the return and the next launch, and this is the chosen place to pay it. "Fixing" it by
  always keeping the line reintroduces a phrase that never changes. See `docs/native-notes.md`,
  "One paint, two audiences".

---

## Build and test

```bash
npm install
npx tsc --noEmit
npm test
cd ios && pod install && cd ..    # only after a JS dependency change
npx expo run:ios
```

**Debug does not link in this project** (`cannot link directly with 'SwiftUICore'`). Build Release
for a device, which is also what you want anyway: it embeds the JS bundle instead of tying the phone
to a running Metro.

`react-native-loupe` is a dev dependency and an on-device debug overlay. It is off unless asked for,
by mechanism rather than by reminder: the require sits inside a `process.env.EXPO_PUBLIC_LOUPE`
branch that Metro folds away before it collects the dependency graph, so an ordinary build carries
none of it.

```bash
EXPO_PUBLIC_LOUPE=1 npx expo run:ios --device <udid> --configuration Release
```

It sees the JavaScript side only. The relay runs in UIKit before React Native has a bridge, so none
of that traffic reaches its panels.

### Tests

`jest-expo`, in `src/**/__tests__/`. `npm test`, or `npm run test:watch`.

Everything worth testing here is a pure function, and the suite covers the four
places where being wrong is SILENT rather than loud:

| Under test | What it costs to get wrong |
| --- | --- |
| `configStore` decoder | every app the user added, with no error |
| `switchLanguageItems` | every phrase the user wrote, with no undo |
| `parseTarget` | a widget tap opening nothing, or the wrong thing |
| `parseQuoteCounts` | a settings screen crashing on a stale blob |
| `RelayGate` (native) | a pinned cover with no way out: a launcher that never launches |
| `RelayReturn` (native) | a missed phrase that cannot be recovered, or one offered forever |

Rules that keep it useful:

- **Test the failure, not the happy path.** Almost every case in
  `configStore.test.ts` is malformed input, because malformed input is what
  actually reaches that code.
- **Prove the test bites.** Before trusting one that guards data, run it against
  the wrong implementation and watch it go red. `switchLanguageItems` has three
  plausible wrong versions and all three fail the suite.
- **No native calls.** `modules/launcher-native` and `expo-crypto` are mocked
  once in `jest.setup.ts`. They are also the only places a test could depend on
  the machine running it, since two of them read the host's locale and region.
- **Fixtures go through a decode.** A quote loaded from disk is never the same
  OBJECT as the bundled one it came from, so a fixture that reuses the bundled
  references passes tests that a real device fails.

`"types": ["jest", "node"]` in `tsconfig.json` is load-bearing: without it the
test globals do not resolve and `npx tsc --noEmit` fails on every suite.

### The one native suite

```bash
./scripts/test-relay-gate
```

`jest-expo` cannot load Swift and the app target has no XCTest bundle, so this
compiles the real `RelayGate.swift` and `RelayReturn.swift` against
`scripts/relay-gate-tests.swift` and runs the cases. **`npm test` does not run
it.** Run it by hand whenever you touch the relay, the cover or either rule.

**Both files may only ever import Foundation.** A single `import UIKit` in
either deletes the native half's only executable test, and nothing will tell
you. It is also why anything needing a window lives in `QuoteScreen` instead.

Time is always an argument here, never a wait: `durationElapsed(_:)` and
`consume(at:)` are called by hand, which is what keeps the cases deterministic.

Full Xcode.app is required. Command Line Tools alone cannot build an iOS app.

**The simulator cannot test tap-to-open.** Third-party schemes fail there with
`LSApplicationWorkspaceErrorDomain` 115. Only `App-Prefs://`, `calshow://` and `photos-redirect://`
resolve, so four of the five bundled defaults are dead. Tap-to-open is only truly testable on a real
iPhone.

Exercise the relay route without a widget:

```bash
xcrun simctl openurl booted 'simplephonern://open?u=App-Prefs%3A%2F%2F'
```

Free personal team, so: 7-day provisioning expiry (the app stops launching roughly weekly, rebuild
and reinstall), 10 App IDs total with app plus widget consuming two per cycle, 3 registered devices.

---

## Git

This repo is a child of the **lifestyle** meta-repo and follows its conventions.

- **Default branch is `master`.**
- **Commit with `/life:commit`.** Do not hand-roll commit messages.
- **Conventional Commits**, English, imperative mood.
- **No emojis. No AI attribution. No `Co-Authored-By` trailer.** A commit message is the one place
  the "subject, not signature" carve-out above does not reach: it never mentions AI at all.
- **Never commit `.env`** or anything holding a secret.
- Do not commit or push without explicit approval. "Continue" is not approval to publish.
- `node_modules/`, `android/`, `ios/Pods/` and `ios/build/` are gitignored and must stay that way.
- **`ios/` is committed.** Do not add it to `.gitignore`.
- The global `~/.gitignore` ignores `src/` (a makepkg build dir on Arch). This repo un-ignores it
  with `!src/`. Do not remove that line: without it the entire app silently vanishes from commits.
