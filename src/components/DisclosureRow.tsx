import { useTheme as useNavigationTheme } from 'expo-router';
import { SymbolView } from 'expo-symbols';
import { Pressable, StyleSheet, Text, View } from 'react-native';

import { useTheme } from '@/store/LauncherStore';

/**
 * The grouped-form chrome, hand-built because there is no `Form` here.
 *
 * `SECTION_INSET + ROW_PADDING` is what puts row labels 36pt from the screen
 * edge, and the preview card at `SECTION_INSET + PREVIEW_INSET` = 32pt, which
 * is the width a systemLarge widget actually occupies on an iPhone. That is why
 * the Swift version set `listRowInsets` to 12 instead of leaving the default.
 *
 * Exported from here because this row is the thing they were measured for.
 * Every screen that draws a card of rows imports both so the insets cannot
 * drift apart between screens.
 */
export const SECTION_INSET = 20;
export const ROW_PADDING = 16;

export interface DisclosureRowProps {
  label: string;
  /**
   * The current setting, drawn greyed to the left of the chevron. Omit it for a
   * row that only navigates and has nothing to summarize.
   */
  value?: string;
  onPress: () => void;
}

/**
 * SwiftUI's `NavigationLink` inside a `Form`: label on the left, current value
 * greyed on the right, chevron after it.
 *
 * It was written once inside the Appearance screen and is now the entire visual
 * vocabulary of the hub, of Appearance and of Phrases. Keeping it in one place
 * is what lets the hub introduce no new shapes -- it is the same row the user
 * already taps everywhere else, just one level up.
 */
export function DisclosureRow({ label, value, onPress }: DisclosureRowProps) {
  const theme = useTheme();
  const { colors } = useNavigationTheme();

  // iOS secondary/tertiary label colors. They follow the launcher theme's Dark
  // switch, like every other surface in the app.
  const secondaryLabel = theme.isDark ? 'rgba(235, 235, 245, 0.6)' : 'rgba(60, 60, 67, 0.6)';
  const tertiaryLabel = theme.isDark ? 'rgba(235, 235, 245, 0.3)' : 'rgba(60, 60, 67, 0.3)';

  return (
    <Pressable accessibilityRole="button" style={styles.row} onPress={onPress}>
      <Text style={[styles.rowLabel, { color: colors.text }]}>{label}</Text>
      <View style={styles.disclosure}>
        {value !== undefined && (
          // A city name has no length limit, so the VALUE is what gives way,
          // never the label. Truncating the label would leave a row whose
          // meaning is gone but whose value is intact.
          <Text style={[styles.value, { color: secondaryLabel }]} numberOfLines={1}>
            {value}
          </Text>
        )}
        <SymbolView
          name="chevron.right"
          size={14}
          weight="semibold"
          tintColor={tertiaryLabel}
          style={styles.chevron}
        />
      </View>
    </Pressable>
  );
}

const styles = StyleSheet.create({
  row: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    minHeight: 44,
    paddingHorizontal: ROW_PADDING,
    paddingVertical: 8,
    gap: 12,
  },
  rowLabel: {
    fontSize: 17,
  },
  disclosure: {
    flexDirection: 'row',
    alignItems: 'center',
    flexShrink: 1,
    gap: 6,
  },
  value: {
    fontSize: 17,
    flexShrink: 1,
  },
  chevron: {
    width: 10,
    height: 16,
  },
});
