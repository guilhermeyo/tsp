import { Link, Stack } from 'expo-router';
import { StyleSheet, Text, View } from 'react-native';

import { useStrings } from '@/i18n/useStrings';
import { useTheme } from '@/store/LauncherStore';
import { fontFamilyFor } from '@/theme/fonts';
import { textColor } from '@/theme/tokens';

/** The brand, injected rather than written into a translatable sentence. */
const APP_SHORT_NAME = 'TSP';

/**
 * Unreachable in normal use -- the app has no URL bar and every link is
 * internal. It exists because Expo Router routes a malformed deep link here,
 * and a bare white "Unmatched" screen would be a jarring way to find out.
 *
 * Themed with the font family and text color, but not the theme's point size:
 * this is app chrome, not launcher content.
 */
export default function NotFoundScreen() {
  const theme = useTheme();
  const s = useStrings();
  const color = textColor(theme);
  const fontFamily = fontFamilyFor(theme.font);

  return (
    <>
      <Stack.Screen options={{ title: s.notFoundTitle }} />
      <View style={styles.container}>
        <Text style={[styles.message, { color, fontFamily }]}>{s.notFoundMessage}</Text>
        <Link href="/" style={[styles.link, { color, fontFamily }]}>
          {s.notFoundLink(APP_SHORT_NAME)}
        </Link>
      </View>
    </>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    alignItems: 'center',
    justifyContent: 'center',
    gap: 12,
    padding: 24,
  },
  message: {
    fontSize: 17,
    textAlign: 'center',
  },
  link: {
    fontSize: 15,
    textDecorationLine: 'underline',
  },
});
