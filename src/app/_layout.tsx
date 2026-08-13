import { DarkTheme, DefaultTheme, Stack, ThemeProvider } from 'expo-router';
import { StatusBar } from 'expo-status-bar';
import { StyleSheet } from 'react-native';
import { GestureHandlerRootView } from 'react-native-gesture-handler';
import { SafeAreaProvider } from 'react-native-safe-area-context';

import { LauncherStoreProvider, useTheme } from '@/store/LauncherStore';

/**
 * Cold-launching straight into the relay would otherwise leave `open` as the
 * only route in the stack: a blank transparent screen with nothing underneath
 * and no back entry. Anchoring the stack to `index` puts the hub below the
 * relay, so a widget tap on a cold start looks exactly like a widget tap on a
 * warm one.
 *
 * `index` used to BE the app list, which is what made the anchor match the
 * Swift app. The list lives at `/apps` now and the anchor deliberately did not
 * follow it: the anchor is what the user is left standing on after dismissing
 * the relay, and that has to be the root of the app, not one section of it.
 * Nothing about the relay changes -- the cover window sits above everything
 * React Native paints, so the round trip stays invisible either way.
 */
export const unstable_settings = { anchor: 'index' };

/**
 * THE RELAY NO LONGER LIVES IN JAVASCRIPT.
 *
 * It is handled in `ios/SimplePhone/AppDelegate.swift`, in Swift, before React
 * Native starts. A widget tap always launches this app -- iOS gives no way
 * around that -- so the only thing under our control is how long it is on
 * screen, and doing it here meant paying a full React Native cold start
 * (Hermes, the bundle, Expo Router mounting, an effect firing) before the
 * target app was even asked to open. The SwiftUI original had no such tax.
 *
 * Do not restore it here. `AppDelegate` returns true WITHOUT forwarding a relay
 * URL to `RCTLinkingManager`, so JavaScript never sees one while the app runs;
 * but on a COLD launch `Linking.getInitialURL()` still reports it, because
 * React Native reads the same launchOptions. An opener on this side would fire
 * a second time and the target app would open, close and open again.
 *
 * `src/app/open.tsx` is no longer reachable through a widget tap either.
 */


/**
 * SwiftUI applied `.preferredColorScheme(theme.colorScheme)` to the WindowGroup,
 * so flipping Dark re-skinned the ENTIRE app: nav bars, Form backgrounds, sheet
 * chrome, keyboard. React Native has no window-level override. The substitute is
 * this ThemeProvider, which drives every navigator's chrome, plus an explicit
 * `keyboardAppearance` on every TextInput in the app.
 *
 * Note what is NOT here: `theme.backgroundColor` is deliberately never painted
 * on any screen of the app -- not the hub, not the list, not a section. In the
 * original only the widget preview card painted it; everything else sat on the
 * standard system background and got its darkness purely from the color scheme.
 * Painting it here would be visibly wrong -- grouped-list insets and separators
 * would lose their contrast against the page.
 */
function ThemedNavigation() {
  const theme = useTheme();

  return (
    <ThemeProvider value={theme.isDark ? DarkTheme : DefaultTheme}>
      <StatusBar style={theme.isDark ? 'light' : 'dark'} />
      <Stack>
        <Stack.Screen
          name="index"
          options={{ title: 'The Simple Phone', headerLargeTitleEnabled: true }}
        />
        {/*
          `presentation: 'modal'` belongs on the PARENT screen, not only on the
          group's own Stack. react-native-screens always places the first screen
          of a stack as a push controller, so a nested navigator can never
          present its own root as a sheet -- the container has to arrive modally.
          The group's inner Stack still sets it, which is what lets the catalog
          rise as a second sheet on top of the form.
        */}
        <Stack.Screen name="(modals)" options={{ headerShown: false, presentation: 'modal' }} />
        <Stack.Screen
          name="open"
          options={{ presentation: 'transparentModal', animation: 'none', headerShown: false }}
        />
      </Stack>
    </ThemeProvider>
  );
}

export default function RootLayout() {
  return (
    // Outermost by requirement of react-native-gesture-handler, which
    // react-native-reorderable-list builds the drag interaction on.
    <GestureHandlerRootView style={styles.root}>
      <SafeAreaProvider>
        <LauncherStoreProvider>
          <ThemedNavigation />
        </LauncherStoreProvider>
      </SafeAreaProvider>
    </GestureHandlerRootView>
  );
}

const styles = StyleSheet.create({
  root: {
    flex: 1,
  },
});
