import type { RowAlignment, TextSize, Theme } from '@/domain/types';

/**
 * Point sizes for the home-screen widget rows. Mirrors `TextSize.widgetPointSize`.
 * Used by the in-app preview card too, so the preview is widget-accurate.
 */
export const WIDGET_POINT_SIZE: Record<TextSize, number> = {
  small: 20,
  medium: 28,
  large: 36,
  extraLarge: 44,
};

/** Point sizes for the in-app list rows, a bit tighter. Mirrors `TextSize.listPointSize`. */
export const LIST_POINT_SIZE: Record<TextSize, number> = {
  small: 17,
  medium: 22,
  large: 28,
  extraLarge: 34,
};

/** Mirrors `Theme.textColor` (`.white` / `.black`). */
export function textColor(theme: Theme): string {
  return theme.isDark ? '#FFFFFF' : '#000000';
}

/**
 * Mirrors `Theme.backgroundColor`. Only the widget preview card paints this;
 * the app's own chrome is standard system chrome driven by the root theme.
 */
export function backgroundColor(theme: Theme): string {
  return theme.isDark ? '#000000' : '#FFFFFF';
}

/**
 * SwiftUI projects one `RowAlignment` three ways: `frameAlignment` places the
 * box, `horizontalAlignment` aligns stacked children, `textAlignment` aligns
 * wrapped lines inside the box. React Native collapses that to two properties,
 * and BOTH are needed on every row: `alignItems`/`textAlign` disagree on a name
 * long enough to wrap, and only applying one of them makes left/right look
 * broken exactly when it matters.
 */
export function flexAlign(alignment: RowAlignment): 'flex-start' | 'center' | 'flex-end' {
  switch (alignment) {
    case 'leading':
      return 'flex-start';
    case 'center':
      return 'center';
    case 'trailing':
      return 'flex-end';
  }
}

export function textAlign(alignment: RowAlignment): 'left' | 'center' | 'right' {
  switch (alignment) {
    case 'leading':
      return 'left';
    case 'center':
      return 'center';
    case 'trailing':
      return 'right';
  }
}
