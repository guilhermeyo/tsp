import { StyleSheet, View } from 'react-native';

import { LauncherRowLabel } from './LauncherRowLabel';

import type { LauncherConfig } from '@/domain/types';
import { useStrings } from '@/i18n/useStrings';
import { backgroundColor, flexAlign } from '@/theme/tokens';

/** Matches `WidgetPreviewCard.limit`. systemLarge shows six rows; so does this. */
const PREVIEW_LIMIT = 6;

export interface WidgetPreviewCardProps {
  config: LauncherConfig;
  limit?: number;
}

/**
 * An in-app mock of the home-screen widget, built from the same row component
 * the real widget uses so the two cannot drift apart visually.
 *
 * This is the ONLY place in the entire app that paints `theme.backgroundColor`.
 * Everything else — the list, the sheets, the nav bars — is standard system
 * chrome that merely looks dark because the root theme says so. Painting the
 * theme background anywhere else would flatten the grouped-list insets against
 * the page and read as a bug.
 */
export function WidgetPreviewCard({ config, limit = PREVIEW_LIMIT }: WidgetPreviewCardProps) {
  const { theme } = config;
  // This is the one thing the card does not take from its `config` prop. Both
  // call sites pass `store.config`, so the stored language and the previewed
  // one are the same value; reading it through the hook instead keeps the empty
  // sentence resolved by exactly the mechanism every other label on the screen
  // uses, which is what stops it drifting into a second resolution path.
  const s = useStrings();
  // Apps 7 and beyond are simply not previewed. No "and N more" indicator: the
  // real widget has no such affordance either, and inventing one here would
  // preview something the widget will never draw.
  const previewed = config.apps.slice(0, limit);

  return (
    <View
      style={[
        styles.card,
        {
          backgroundColor: backgroundColor(theme),
          // `Color.primary` follows the app's color scheme, which the theme's
          // Dark switch drives, so the hairline flips with it.
          borderColor: theme.isDark ? 'rgba(255, 255, 255, 0.12)' : 'rgba(0, 0, 0, 0.12)',
        },
      ]}
    >
      {/*
        The Swift VStack carries the alignment too. It changes nothing while
        every row stretches to full width — same as in SwiftUI — but it is part
        of the shape being mirrored, and it would start mattering the moment a
        row stopped stretching.
      */}
      <View style={[styles.rows, { alignItems: flexAlign(theme.alignment) }]}>
        {previewed.length === 0 ? (
          // The DECLARED TWIN of `emptyMessage` in
          // `ios/SimplePhoneWidget/WidgetViews.swift`, which draws the same
          // sentence on the home screen from a Swift switch it cannot share with
          // this catalog: the extension's `Bundle.main` is the .appex and cannot
          // read the app's quotes.json. All four languages must match that
          // switch word for word, or this preview disagrees with the widget
          // sitting behind it. The bundled app NAMES stay Portuguese whatever
          // this says -- they are user data, not copy.
          <LauncherRowLabel name={s.widgetLauncherEmpty} theme={theme} dimmed lineLimit={2} />
        ) : (
          previewed.map((app) => <LauncherRowLabel key={app.id} name={app.name} theme={theme} />)
        )}
      </View>
    </View>
  );
}

const styles = StyleSheet.create({
  card: {
    alignSelf: 'stretch',
    justifyContent: 'center',
    minHeight: 240,
    padding: 20,
    // The Swift version clips to a CONTINUOUS rounded rectangle (Apple's
    // squircle). React Native only has circular corners, so the curvature at
    // the corner transition is slightly tighter here than on the real widget.
    // Nothing in the layout depends on it; it is a few pixels of shape.
    borderRadius: 24,
    overflow: 'hidden',
    borderWidth: 1,
  },
  rows: {
    gap: 16,
  },
});
