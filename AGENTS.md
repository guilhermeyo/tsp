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

Specifically stale advice to ignore: "bare vs managed workflow" (replaced by CNG, see
`docs/native-notes.md` part 3), the old bridge module API with `RCT_EXPORT_METHOD` (replaced by the
Expo Modules API), and anything about `expo eject` (that command no longer exists).

---

## Repo shape

```
app.json                  the app target's spec. Replaced the old project.yml.
targets/widget/           Swift for the WidgetKit extension.        COMMITTED. SOURCE.
modules/launcher-native/  Swift for the local Expo module.          COMMITTED. SOURCE.
src/                      the React Native app. TypeScript, strict.
docs/                     teaching notes.
ios/                      generated Xcode project.                  GITIGNORED. OUTPUT.
```

**`targets/` and `modules/` are the committed native surface. `ios/` is disposable.**

### Never hand-edit the generated project

This rule predates the Expo port. The old setup generated `SimplePhone.xcodeproj` with XcodeGen from
a committed `project.yml` and gitignored the result. Same rule, new generator.

Any change you make inside `ios/`, whether by editing files or by clicking around in Xcode, is
destroyed by the next prebuild, with no prompt and no warning. As of SDK 57, `npx expo prebuild`
clears and regenerates the native directories **by default**.

Changes belong in one of exactly three places:

| What you want to change              | Where it goes                          |
| ------------------------------------ | -------------------------------------- |
| Bundle id, scheme, entitlements, plist | `app.json`                           |
| The widget extension target          | `targets/widget/expo-target.config.js` |
| Anything else in the Xcode project   | a config plugin                        |

Always regenerate with `--clean`. Incremental prebuild has open upstream bugs when updating an
existing Apple target:

```bash
npx expo prebuild -p ios --clean
cd ios && pod install && cd ..
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

This is why `@bacons/apple-targets`' bundled `ExtensionStorage` is deliberately unused. Full chain
in `README.md`.

### 2. Never rename the widget `kind` string

`"SimplePhoneLauncher"` in `targets/widget/LauncherWidget.swift`. WidgetKit persists it for widgets
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

The App Group id appears literally in `app.json` and in
`targets/widget/expo-target.config.js`. A stray space fails signing with a message that does not
mention the group. Verify after prebuild:

```bash
plutil -p ios/SimplePhone/SimplePhone.entitlements
plutil -p ios/.targets/SimplePhoneWidget/generated.entitlements
```

---

## The deep link scheme is `simplephonern`

Not `simplephone`. The old native Swift app owns that one and may still be installed on the same
device. Two apps registering the same scheme means iOS picks a winner arbitrarily.

Widget rows link to `simplephonern://open?u=<encoded target>`. The scheme string lives in three
places that must agree: `app.json`, `targets/widget/DeepLink.swift`, `src/domain/deepLink.ts`.

A widget tap can never open a third-party app directly. Never put a third-party scheme in a widget
`Link` or `widgetURL`. See the relay story in `README.md`.

---

## Code rules

- **TypeScript strict.** No `any`, no `@ts-ignore`. `npx tsc --noEmit` must be clean before any
  commit.
- **No emojis anywhere.** Not in code, not in UI strings, not in commits, not in docs.
- **No AI mentions** in code, comments, commits or docs.
- **English everywhere.** Code, comments, commits, docs. The only exceptions are the five bundled
  default app names, which are Portuguese because they are user data inherited from the original
  app, and must stay byte-identical.
- **Comment WHY, not WHAT.** The native files are teaching material and should be commented
  generously. Obvious TypeScript should not be commented at all.
- The `?? .standard` fallback in `ConfigStore.swift` and `LauncherNativeModule.swift` is
  intentional. Do not remove it. See the App Group story in `README.md`.

### Do not "fix" these

They look like bugs. They are faithful ports of deliberate behavior:

- `placeholder` uses `LauncherConfig.default` while `getSnapshot` uses `ConfigStore.load()`.
- `Timeline(policy: .never)` with no time-based refresh.
- Two rendering paths in `WidgetViews.swift` (`Link` does not work in `systemSmall`).
- Deep-link failure is a silent no-op with a `TODO`. No alert, no toast.
- Delete has no confirmation, on either of the two delete paths.
- The Appearance screen has no Done button. Every edit commits live; swipe-down is the exit.
- "Choose from catalog" prefills the form only. It never adds or saves anything.
- Empty-state text uses the theme's font family but not the theme's size.
- The list has no separators.

---

## Build and test

```bash
npm install
npx tsc --noEmit
npx expo prebuild -p ios --clean
cd ios && pod install && cd ..
npx expo run:ios
```

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
- **No emojis. No AI mentions. No `Co-Authored-By` trailer.**
- **Never commit `.env`** or anything holding a secret.
- Do not commit or push without explicit approval. "Continue" is not approval to publish.
- `ios/`, `android/` and `node_modules/` are gitignored and must stay that way.
