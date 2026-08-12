/**
 * Declares the native iOS WidgetKit extension target.
 *
 * `@bacons/apple-targets` reads this during `expo prebuild` and creates a real
 * app-extension target in the generated Xcode project, compiling every Swift
 * file in this folder into it and embedding it in the host app.
 *
 * This folder lives OUTSIDE `ios/`, which is what makes it survive
 * `expo prebuild --clean`. `ios/` is disposable output; this is source.
 *
 * @type {import('@bacons/apple-targets/app.plugin').Config}
 */
module.exports = {
  type: 'widget',
  name: 'SimplePhoneWidget',
  deploymentTarget: '17.0',
  frameworks: ['SwiftUI', 'WidgetKit'],
  entitlements: {
    // MUST stay byte-identical to ios.entitlements in app.json — the App Group
    // is the only channel between the React Native app and this extension.
    'com.apple.security.application-groups': ['group.com.guilherme44.simple-phone'],
  },
};
