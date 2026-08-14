# CLAUDE.md

`AGENTS.md` is the canonical rules file for this repo. Read it before writing anything.

@AGENTS.md

## Before you start

1. **Expo has changed.** Read https://docs.expo.dev/versions/v57.0.0/ for anything Expo-specific
   rather than answering from memory. SDK 57, RN 0.86.2, React 19.2.3, TypeScript 6.
2. **`README.md`** explains what the app is, why the widget is SwiftUI, the relay, the App Group,
   and why this is a **bare** project (`ios/` is committed source, not generated output).
3. **`docs/native-notes.md`** explains WidgetKit and the Expo Modules API. Read it before touching
   any `.swift` file.

## The four ways to lose

In rough order of how much damage they do and how quietly they do it:

1. Writing config through an object-bridging API instead of `JSON.stringify`. Silently wipes every
   app the user added.
2. Renaming the widget `kind` string `"SimplePhoneLauncher"`. Blanks every already-placed widget.
3. Running `npx expo prebuild`. `ios/` is committed source here; prebuild clears and regenerates it
   by default, deleting the Xcode project, both targets and every hand edit, with no prompt.
4. Breaking the App Group id's byte-for-byte match between
   `ios/SimplePhone/SimplePhone.entitlements` and
   `ios/SimplePhoneWidget/SimplePhoneWidget.entitlements`. Signing fails with an
   unrelated-looking error.

All four are explained in `AGENTS.md`.

## Working here

- `npx tsc --noEmit` and `npm test` must both be clean before you claim anything is done.
- Comment the native side generously and the obvious TypeScript not at all. The point of this repo
  is learning the native half.
- This is a child of the **lifestyle** meta-repo: default branch `master`, commits via
  `/life:commit`, Conventional Commits, no emojis, no AI attribution, no `Co-Authored-By`. Commits
  and code carry no AI credit at all; `README.md` and `docs/` may write about AI as a subject. See
  "Code rules" in `AGENTS.md`.
- Do not commit or push without explicit approval.
