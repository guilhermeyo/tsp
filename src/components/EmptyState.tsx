import { SymbolView } from 'expo-symbols';
import { StyleSheet, Text, View } from 'react-native';

import { useStrings } from '@/i18n/useStrings';
import { useTheme } from '@/store/LauncherStore';
import { fontFamilyFor } from '@/theme/fonts';
import { textColor } from '@/theme/tokens';

/** `Color.secondary`, i.e. `UIColor.secondaryLabel`, in both appearances. */
function secondaryColor(isDark: boolean): string {
  return isDark ? 'rgba(235, 235, 245, 0.6)' : 'rgba(60, 60, 67, 0.6)';
}

/**
 * Shown INSTEAD of the list when there are no apps -- the original does not
 * render an empty List, it renders this.
 *
 * The two strings follow the theme's font FAMILY but keep the semantic headline
 * (17pt) and subheadline (15pt) sizes. They must not scale with the theme's size
 * setting: only real launcher rows do that. `theme.resolvedFont(.headline)` in
 * the original is `.system(.headline, design:)`, which is exactly this split.
 */
export function EmptyState() {
  const theme = useTheme();
  const s = useStrings();
  const fontFamily = fontFamilyFor(theme.font);
  const secondary = secondaryColor(theme.isDark);

  return (
    <View style={styles.container}>
      <SymbolView
        name="square.grid.2x2"
        size={34}
        tintColor={secondary}
        style={styles.icon}
        accessibilityElementsHidden
      />
      <Text style={[styles.headline, { fontFamily, color: textColor(theme) }]}>
        {s.emptyAppsTitle}
      </Text>
      {/* The '+' naming the toolbar button lives INSIDE the translated sentence
          rather than being spliced around it, so each language can place the
          glyph where its own grammar wants it. */}
      <Text style={[styles.subheadline, { fontFamily, color: secondary }]}>{s.emptyAppsBody}</Text>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    alignItems: 'center',
    justifyContent: 'center',
    gap: 12,
    padding: 16,
  },
  icon: {
    width: 34,
    height: 34,
  },
  headline: {
    fontSize: 17,
    fontWeight: '600',
  },
  subheadline: {
    fontSize: 15,
    textAlign: 'center',
  },
});
