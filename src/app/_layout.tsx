import * as Linking from 'expo-linking';
import { DarkTheme, DefaultTheme, Stack, ThemeProvider } from 'expo-router';
import { StatusBar } from 'expo-status-bar';
import { useEffect } from 'react';
import { StyleSheet } from 'react-native';
import { GestureHandlerRootView } from 'react-native-gesture-handler';
import { SafeAreaProvider } from 'react-native-safe-area-context';

import { parseTarget } from '@/domain/deepLink';
import { LauncherStoreProvider, useTheme } from '@/store/LauncherStore';

/**
 * Cold-launching straight into the relay would otherwise leave `open` as the
 * only route in the stack: a blank transparent screen with nothing underneath
 * and no back entry. Anchoring the stack to `index` puts the app list below the
 * relay, so a widget tap on a cold start looks exactly like a widget tap on a
 * warm one, and matches the Swift app, which always showed the list.
 */
export const unstable_settings = { anchor: 'index' };

/**
 * Opens the third-party URL a widget row asked for. Twin of `URLRelay.handle`.
 *
 * Lives here, at the root, rather than inside `open.tsx`, for two reasons.
 *
 * The faithful one: the Swift app registered `.onOpenURL` on its WindowGroup,
 * not on a screen. The relay was never a view; it was a side effect of the
 * window receiving a URL, which is why it dismissed nothing and did not care
 * what was on top.
 *
 * The load-bearing one: Expo Router will route the same URL to `open.tsx`, but
 * it mangles the payload on the way. Its `extractExpoPathFromURL` percent-decodes
 * the whole query and re-emits it as a plain path string, which is then parsed
 * as a query a second time. `simplephonern://open?u=https%3A%2F%2Fx.com%2Fs%3Fq%3Da%26b%3Dc`
 * becomes the path `open?u=https://x.com/s?q=a&b=c`, and `u` comes back
 * truncated at the first `&`. A target carrying its own percent-escape gets
 * decoded twice on top of that. So the raw URL is parsed here, once, by
 * `parseTarget`, and `open.tsx` never touches the payload at all.
 */
function relayDeepLink(url: string): void {
  const target = parseTarget(url);
  if (target === null) return;

  // `UIApplication.shared.open(target)` with a completion handler that ignores
  // `success == false`. If the target app is not installed, the old app showed
  // no alert, no toast and no App Store fallback -- it opened, showed the list
  // and sat there. The empty catch reproduces that. It is a known gap carrying
  // a TODO in the original, not a bug to accidentally fix.
  Linking.openURL(target).catch(() => {});
}

/**
 * The launch URL must be consumed exactly once per JS runtime. The root layout
 * mounts once in production, but React can double-invoke effects in dev, and
 * `getInitialURL` keeps returning the launch URL forever -- without this the
 * target app would be re-opened on every remount.
 */
let coldStartURLConsumed = false;

function useDeepLinkRelay(): void {
  useEffect(() => {
    // iOS delivers a URL to a RUNNING app through `application:openURL:`, which
    // RCTLinkingManager forwards as this event. A cold launch instead carries
    // the URL in `launchOptions`, and by the time JS is listening the moment has
    // passed -- hence the two separate paths below. They never both fire for the
    // same URL.
    const subscription = Linking.addEventListener('url', (event) => {
      relayDeepLink(event.url);
    });

    if (!coldStartURLConsumed) {
      coldStartURLConsumed = true;
      Linking.getInitialURL()
        .then((url) => {
          // `getLinkingURL` is the Expo-native reader Expo Router itself uses for
          // iOS cold starts; it covers the cases where RCTLinkingManager's
          // launchOptions copy comes back empty.
          const launchURL = url ?? Linking.getLinkingURL();
          if (launchURL !== null) relayDeepLink(launchURL);
        })
        .catch(() => {});
    }

    return () => subscription.remove();
  }, []);
}

/**
 * SwiftUI applied `.preferredColorScheme(theme.colorScheme)` to the WindowGroup,
 * so flipping Dark re-skinned the ENTIRE app: nav bars, Form backgrounds, sheet
 * chrome, keyboard. React Native has no window-level override. The substitute is
 * this ThemeProvider, which drives every navigator's chrome, plus an explicit
 * `keyboardAppearance` on every TextInput in the app.
 *
 * Note what is NOT here: `theme.backgroundColor` is deliberately never painted
 * on the list. In the original only the widget preview card painted it; the
 * list sat on the standard system List background and got its darkness purely
 * from the color scheme. Painting it here would be visibly wrong -- grouped-list
 * insets and separators would lose their contrast against the page.
 */
function ThemedNavigation() {
  const theme = useTheme();

  return (
    <ThemeProvider value={theme.isDark ? DarkTheme : DefaultTheme}>
      <StatusBar style={theme.isDark ? 'light' : 'dark'} />
      <Stack>
        <Stack.Screen
          name="index"
          options={{ title: 'Simple Phone', headerLargeTitleEnabled: true }}
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
  useDeepLinkRelay();

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
