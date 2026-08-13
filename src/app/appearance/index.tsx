import { Stack, useRouter, useTheme as useNavigationTheme } from 'expo-router';
import { ScrollView, StyleSheet, Switch, Text, View } from 'react-native';

import { DisclosureRow, ROW_PADDING, SECTION_INSET } from '@/components/DisclosureRow';
import { SegmentedControl } from '@/components/SegmentedControl';
import { WidgetPreviewCard } from '@/components/WidgetPreviewCard';
import { ROW_ALIGNMENTS, type RowAlignment } from '@/domain/types';
import { useStrings } from '@/i18n/useStrings';
import { useLauncherStore } from '@/store/LauncherStore';

/** See DisclosureRow for what SECTION_INSET and ROW_PADDING are measured from. */
const PREVIEW_INSET = 12;

/**
 * How the launcher rows LOOK: dark, face, alignment, size. Nothing else.
 *
 * It used to also own the phrase settings, on the argument that a phrase is the
 * look of the launch rather than a separate feature. That argument lost when
 * the root became a hub: Phrases is a section of its own now, one tap from the
 * same place this screen is.
 *
 * There is no Done button here any more either. It existed because this screen
 * arrived as a sheet, and interactive sheet dismissal is not always available
 * (Switch Control, Voice Control), so without a visible exit the screen could
 * become a trap. It is a pushed screen now and wears a back chevron, which is
 * that exit. Every control still commits the instant it is touched, so there
 * has never been anything to confirm.
 */
export default function AppearanceScreen() {
  const store = useLauncherStore();
  const theme = store.config.theme;
  const router = useRouter();
  const { colors } = useNavigationTheme();
  const s = useStrings();

  const secondaryLabel = theme.isDark ? 'rgba(235, 235, 245, 0.6)' : 'rgba(60, 60, 67, 0.6)';

  function selectAlignment(alignment: RowAlignment): void {
    store.updateTheme({ alignment });
  }

  return (
    <>
      <Stack.Screen options={{ title: s.sectionAppearance, headerLargeTitleEnabled: true }} />
      <ScrollView
        // Required for the large title to collapse into the bar on scroll —
        // the native header measures the scroll view's adjusted inset.
        contentInsetAdjustmentBehavior="automatic"
        style={{ backgroundColor: colors.background }}
        contentContainerStyle={styles.content}
      >
        <Text style={[styles.sectionHeader, { color: secondaryLabel }]}>
          {s.appearanceSectionPreview}
        </Text>
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
            <Text style={[styles.rowLabel, { color: colors.text }]}>{s.appearanceDark}</Text>
            <Switch
              value={theme.isDark}
              onValueChange={(isDark) => store.updateTheme({ isDark })}
            />
          </View>

          <View style={[styles.separator, { backgroundColor: colors.border }]} />

          <DisclosureRow
            label={s.sectionFont}
            value={s.fontLabels[theme.font]}
            onPress={() => router.push('/appearance/font')}
          />

          <View style={[styles.separator, { backgroundColor: colors.border }]} />

          {/*
            SwiftUI's segmented picker style discards the picker's label, so the
            original row is the control alone, full width, with the word
            "Alignment" nowhere on screen. Kept as-is for fidelity; the label
            survives for VoiceOver.
          */}
          <View style={styles.segmentRow}>
            <SegmentedControl
              accessibilityLabel={s.a11yAlignment}
              options={ROW_ALIGNMENTS}
              labels={s.alignmentLabels}
              value={theme.alignment}
              onChange={selectAlignment}
              isDark={theme.isDark}
            />
          </View>

          <View style={[styles.separator, { backgroundColor: colors.border }]} />

          <DisclosureRow
            label={s.sectionSize}
            value={s.sizeLabels[theme.size]}
            onPress={() => router.push('/appearance/size')}
          />
        </View>
      </ScrollView>
    </>
  );
}

const styles = StyleSheet.create({
  content: {
    paddingBottom: 32,
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
    // The Switch beside it has a fixed intrinsic width and will not give way, so
    // the label has to. Nothing today is long enough to need it -- Dark is one
    // word in all four languages -- but this is the only row on the screen where
    // an overlong label would push a control off the edge instead of truncating.
    flexShrink: 1,
  },
  // A column, so the control stretches across the row instead of being packed
  // against one edge the way a labelled row's accessory is.
  segmentRow: {
    justifyContent: 'center',
    minHeight: 44,
    paddingHorizontal: ROW_PADDING,
    paddingVertical: 8,
  },
  separator: {
    height: StyleSheet.hairlineWidth,
    marginLeft: ROW_PADDING,
  },
});
