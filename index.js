// The app's entry point exists only so Loupe can be the very first thing that
// runs. It patches fetch, XHR, console and the deep-link handlers, and
// `expo-router/entry` starts the whole app the moment it is loaded, so the
// order of these two matters and is the whole reason this file is here.
//
// `main` in package.json points here instead of at `expo-router/entry`.
//
// OFF UNLESS ASKED FOR, and the shape of this block is what makes that true
// rather than a promise. Metro replaces `process.env.EXPO_PUBLIC_LOUPE` with a
// literal at build time and folds the dead branch away BEFORE it collects the
// file's dependency graph, so an ordinary build never reaches the require and
// none of Loupe enters the bundle. A top-level import would undo all of it.
//
// Loupe's own default entry gates itself behind `__DEV__`, which would be the
// obvious way to do this and does not work here: Debug will not link in this
// project (`cannot link directly with 'SwiftUICore'`), and a Debug build would
// tie the phone to a running Metro anyway. Hence the release entry plus a
// switch of our own.
//
//     EXPO_PUBLIC_LOUPE=1 npx expo run:ios --device <udid> --configuration Release
//
// Turn it on only for a build going to someone who should see it: the panels
// display network bodies, stored values and logs.
//
// It sees the JavaScript side. The relay that covers a widget tap with a
// phrase runs in UIKit inside `application(_:open:options:)`, before React
// Native has a bridge, so none of that traffic reaches these panels.
if (process.env.EXPO_PUBLIC_LOUPE === '1') {
  // The release entry does not start on import, and the dev menu that shake
  // would fall back to does not exist in a release build. The draggable bubble
  // is the way in.
  require('react-native-loupe/release').startLoupe({ shake: false });
}

import 'expo-router/entry';
