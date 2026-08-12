import { Stack, useRouter, useTheme as useNavigationTheme } from 'expo-router';
import { SymbolView } from 'expo-symbols';
import { useMemo } from 'react';
import { Pressable, ScrollView, StyleSheet, Switch, Text, View } from 'react-native';

import { SegmentedControl } from '@/components/SegmentedControl';
import { WidgetPreviewCard } from '@/components/WidgetPreviewCard';
import {
  ALIGNMENT_LABELS,
  FONT_LABELS,
  ROW_ALIGNMENTS,
  SIZE_LABELS,
  type RowAlignment,
} from '@/domain/types';
import { useLauncherStore } from '@/store/LauncherStore';

/**
 * The grouped-form chrome, hand-built because there is no `Form` here.
 *
 * `SECTION_INSET + ROW_PADDING` is what puts row labels 36pt from the screen
 * edge, and the preview card at `SECTION_INSET + PREVIEW_INSET` = 32pt, which
 * is the width a systemLarge widget actually occupies on an iPhone. That is why
 * the Swift version set `listRowInsets` to 12 instead of leaving the default.
 */
const SECTION_INSET = 20;
const ROW_PADDING = 16;
const PREVIEW_INSET = 12;

export default function AppearanceScreen() {
  const store = useLauncherStore();
  const theme = store.config.theme;
  const router = useRouter();
  const { colors } = useNavigationTheme();

  // iOS secondary/tertiary label colors. They follow the launcher theme's Dark
  // switch, like every other surface in the app.
  const secondaryLabel = theme.isDark ? 'rgba(235, 235, 245, 0.6)' : 'rgba(60, 60, 67, 0.6)';
  const tertiaryLabel = theme.isDark ? 'rgba(235, 235, 245, 0.3)' : 'rgba(60, 60, 67, 0.3)';

  /**
   * THE ONE DELIBERATE DIVERGENCE FROM THE ORIGINAL.
   *
   * The Swift screen has no Done, Close, Save or Cancel button at all: swipe
   * down is the only way out, and that is coherent because every control here
   * commits the instant it is touched, so there is nothing to confirm or undo.
   *
   * This Done button does NOT change that model. It confirms nothing, cancels
   * nothing and saves nothing — the config was already written before the user
   * reached for it. It exists because interactive sheet dismissal is not always
   * available (Switch Control, Voice Control, a non-iOS host), and without a
   * visible exit the screen becomes a trap on those paths.
   *
   * Memoized so the options object keeps its identity: `Stack.Screen` calls
   * `setOptions` whenever the object changes, and an inline literal would do
   * that on every render.
   */
  const screenOptions = useMemo(
    () => ({
      title: 'Appearance',
      headerLargeTitleEnabled: true,
      headerRight: () => (
        <Pressable accessibilityRole="button" hitSlop={12} onPress={() => router.back()}>
          <Text style={[styles.done, { color: colors.primary }]}>Done</Text>
        </Pressable>
      ),
    }),
    [colors.primary, router]
  );

  function selectAlignment(alignment: RowAlignment): void {
    store.updateTheme({ alignment });
  }

  return (
    <>
      <Stack.Screen options={screenOptions} />
      <ScrollView
        // Required for the large title to collapse into the bar on scroll —
        // the native header measures the scroll view's adjusted inset.
        contentInsetAdjustmentBehavior="automatic"
        style={{ backgroundColor: colors.background }}
        contentContainerStyle={styles.content}
      >
        <Text style={[styles.sectionHeader, { color: secondaryLabel }]}>Widget preview</Text>
        {/*
          No card behind it: the Swift row used a clear `listRowBackground` so
          the preview floats directly on the form. Every control below rewrites
          the config, and this re-renders from it on the same tick.
        */}
        <View style={styles.previewRow}>
          <WidgetPreviewCard config={store.config} />
        </View>

        {/* The second section is unlabelled, and the order of these four is fixed. */}
        <View style={[styles.card, { backgroundColor: colors.card }]}>
          <View style={styles.row}>
            <Text style={[styles.rowLabel, { color: colors.text }]}>Dark</Text>
            <Switch
              value={theme.isDark}
              onValueChange={(isDark) => store.updateTheme({ isDark })}
            />
          </View>

          <View style={[styles.separator, { backgroundColor: colors.border }]} />

          <Pressable
            accessibilityRole="button"
            style={styles.row}
            onPress={() => router.push('/(modals)/appearance/font')}
          >
            <Text style={[styles.rowLabel, { color: colors.text }]}>Font</Text>
            <View style={styles.disclosure}>
              <Text style={[styles.value, { color: secondaryLabel }]}>
                {FONT_LABELS[theme.font]}
              </Text>
              <SymbolView
                name="chevron.right"
                size={14}
                weight="semibold"
                tintColor={tertiaryLabel}
                style={styles.chevron}
              />
            </View>
          </Pressable>

          <View style={[styles.separator, { backgroundColor: colors.border }]} />

          {/*
            SwiftUI's segmented picker style discards the picker's label, so the
            original row is the control alone, full width, with the word
            "Alignment" nowhere on screen. Kept as-is for fidelity; the label
            survives for VoiceOver.
          */}
          <View style={styles.segmentRow}>
            <SegmentedControl
              accessibilityLabel="Alignment"
              options={ROW_ALIGNMENTS}
              labels={ALIGNMENT_LABELS}
              value={theme.alignment}
              onChange={selectAlignment}
              isDark={theme.isDark}
            />
          </View>

          <View style={[styles.separator, { backgroundColor: colors.border }]} />

          <Pressable
            accessibilityRole="button"
            style={styles.row}
            onPress={() => router.push('/(modals)/appearance/size')}
          >
            <Text style={[styles.rowLabel, { color: colors.text }]}>Size</Text>
            <View style={styles.disclosure}>
              <Text style={[styles.value, { color: secondaryLabel }]}>
                {SIZE_LABELS[theme.size]}
              </Text>
              <SymbolView
                name="chevron.right"
                size={14}
                weight="semibold"
                tintColor={tertiaryLabel}
                style={styles.chevron}
              />
            </View>
          </Pressable>
        </View>
      </ScrollView>
    </>
  );
}

const styles = StyleSheet.create({
  content: {
    paddingBottom: 32,
  },
  done: {
    fontSize: 17,
    fontWeight: '600',
  },
  sectionHeader: {
    fontSize: 13,
    // SwiftUI's Form renders section headers as written. UIKit's grouped table
    // uppercases them; do not "restore" that here.
    paddingHorizontal: SECTION_INSET + ROW_PADDING,
    paddingTop: 24,
    paddingBottom: 8,
  },
  previewRow: {
    paddingHorizontal: SECTION_INSET + PREVIEW_INSET,
    paddingVertical: PREVIEW_INSET,
  },
  card: {
    marginTop: 24,
    marginHorizontal: SECTION_INSET,
    borderRadius: 10,
    overflow: 'hidden',
  },
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
  // A column, so the control stretches across the row instead of being packed
  // against one edge the way a labelled row's accessory is.
  segmentRow: {
    justifyContent: 'center',
    minHeight: 44,
    paddingHorizontal: ROW_PADDING,
    paddingVertical: 8,
  },
  disclosure: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 6,
  },
  value: {
    fontSize: 17,
  },
  chevron: {
    width: 10,
    height: 16,
  },
  separator: {
    height: StyleSheet.hairlineWidth,
    marginLeft: ROW_PADDING,
  },
});
