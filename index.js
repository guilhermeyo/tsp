// The app's entry point exists only so Loupe can be the very first thing that
// runs. It patches fetch, XHR, console and the deep-link handlers, and
// `expo-router/entry` starts the whole app the moment it is loaded, so the
// order of these two imports is the whole reason this file exists.
//
// `main` in package.json points here instead of at `expo-router/entry`.
//
// THIS IS THE RELEASE ENTRY, AND IT SHIPS. The default `react-native-loupe`
// import gates everything behind `__DEV__` and leaves nothing in a release
// bundle, which is the right choice and not the one made here: Debug will not
// link for this project (`cannot link directly with 'SwiftUICore'`), and a
// Debug build would tie the phone to a running Metro anyway. So the overlay is
// switched on in the build that actually runs on the device.
//
// REMOVE BOTH LINES BEFORE SUBMITTING TO THE APP STORE. The panels display
// network bodies, stored values and logs, which is a debugging tool in the
// hands of a tester and a leak in the hands of a stranger.
//
// Loupe sees the JavaScript side only. The relay that covers a widget tap with
// a phrase runs in UIKit inside `application(_:open:options:)`, before React
// Native has a bridge, so none of that traffic reaches these panels.
// `ios/SimplePhone/QuoteScreen.swift` writes its own trace to
// `Documents/relay-trace.log`, which is what actually found the timing bug.
import { startLoupe } from 'react-native-loupe/release';

// Explicit, because the release entry does not start on import and the dev
// menu that shake falls back to does not exist here. The draggable bubble is
// the way in.
startLoupe({ shake: false });

import 'expo-router/entry';
