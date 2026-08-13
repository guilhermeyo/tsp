import { StyleSheet, Text, View } from 'react-native';

import type { Theme } from '@/domain/types';
import { fontFamilyFor } from '@/theme/fonts';
import { WIDGET_POINT_SIZE, flexAlign, textAlign, textColor } from '@/theme/tokens';

/**
 * TWIN FILE — change this and `ios/SimplePhoneWidget/LauncherRowLabel.swift` together.
 *
 * In the old codebase there was exactly ONE row component, a Swift file in
 * `Shared/` compiled into both the app and the widget extension, so the in-app
 * preview and the home screen could not physically disagree. That guarantee is
 * gone: the widget is still Swift and the preview is now React Native, so the
 * same visual contract lives in two languages. What used to be enforced by the
 * compiler is now enforced by this comment.
 *
 * Every property below is a deliberate mirror of the Swift original:
 * font family, 20/28/36/44 point size, semibold weight, 0.5 dim, line limit,
 * shrink-to-fit and the two-axis alignment. None of them are free to drift.
 */
export interface LauncherRowLabelProps {
  name: string;
  theme: Theme;
  dimmed?: boolean;
  lineLimit?: number;
}

export function LauncherRowLabel({
  name,
  theme,
  dimmed = false,
  lineLimit = 1,
}: LauncherRowLabelProps) {
  return (
    // SwiftUI expressed one `RowAlignment` on two axes at once:
    // `.frame(maxWidth: .infinity, alignment:)` parks the text block inside a
    // full-width box, and `.multilineTextAlignment` aligns the individual lines
    // within that block. React Native needs both too — `alignItems` here does
    // the first job, `textAlign` below does the second — and they only visibly
    // disagree on a name long enough to wrap, which is exactly the case that
    // makes a one-axis port look broken.
    <View style={[styles.frame, { alignItems: flexAlign(theme.alignment) }]}>
      <Text
        numberOfLines={lineLimit}
        // The widget has a fixed canvas and no scrolling, so a name that does
        // not fit SHRINKS instead of truncating. Half size is the floor, same
        // as `.minimumScaleFactor(0.5)`.
        adjustsFontSizeToFit
        minimumFontScale={0.5}
        style={[
          styles.label,
          {
            fontFamily: fontFamilyFor(theme.font),
            // The WIDGET table (20/28/36/44), not the in-app list table
            // (17/22/28/34), even though this renders inside the app. The
            // preview's whole job is to be widget-accurate; shrinking it to
            // list sizes would make the preview lie.
            fontSize: WIDGET_POINT_SIZE[theme.size],
            color: textColor(theme),
            opacity: dimmed ? 0.5 : 1,
            textAlign: textAlign(theme.alignment),
          },
        ]}
      >
        {name}
      </Text>
    </View>
  );
}

const styles = StyleSheet.create({
  frame: {
    alignSelf: 'stretch',
  },
  label: {
    // Semibold is fixed. The theme controls family and size, never weight.
    fontWeight: '600',
  },
});
