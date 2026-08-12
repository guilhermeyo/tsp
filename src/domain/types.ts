/**
 * The TypeScript half of the data contract with the Swift widget.
 *
 * Every string literal in this file is a Swift enum raw value, byte-for-byte.
 * They travel through JSON into `targets/widget/Theme.swift`, where Swift's
 * `Codable` matches them by exact string. A single renamed case here (say
 * 'extralarge' instead of 'extraLarge') makes `decodeIfPresent` return the
 * default and the widget silently drifts from the app.
 */

/** Mirrors `FontChoice` in targets/widget/Theme.swift. */
export type FontChoice = 'monospaced' | 'system' | 'rounded' | 'serif';

/** Mirrors `RowAlignment` in targets/widget/Theme.swift. */
export type RowAlignment = 'leading' | 'center' | 'trailing';

/** Mirrors `TextSize` in targets/widget/Theme.swift. `extraLarge` is camelCase in Swift too. */
export type TextSize = 'small' | 'medium' | 'large' | 'extraLarge';

/** Every case, in the order Swift's `CaseIterable` yields them (declaration order). */
export const FONT_CHOICES: readonly FontChoice[] = ['monospaced', 'system', 'rounded', 'serif'];
export const ROW_ALIGNMENTS: readonly RowAlignment[] = ['leading', 'center', 'trailing'];
export const TEXT_SIZES: readonly TextSize[] = ['small', 'medium', 'large', 'extraLarge'];

/**
 * One launchable row. `id` is a UUID string: Swift encodes `UUID` as an
 * uppercase string and `UUID(uuidString:)` parses case-insensitively, so the
 * lowercase ids minted by `Crypto.randomUUID()` round-trip fine.
 */
export interface LauncherApp {
  id: string;
  name: string;
  urlString: string;
}

/** Mirrors `Theme` in targets/widget/Theme.swift. */
export interface Theme {
  isDark: boolean;
  font: FontChoice;
  alignment: RowAlignment;
  size: TextSize;
}

/** The single serialized unit of shared state. Mirrors `LauncherConfig`. */
export interface LauncherConfig {
  apps: LauncherApp[];
  theme: Theme;
}

/** Mirrors `Theme.default`. Also the per-field fallback for resilient decoding. */
export const DEFAULT_THEME: Theme = {
  isDark: true,
  font: 'monospaced',
  alignment: 'center',
  size: 'large',
};

/** Mirrors `FontChoice.label`. */
export const FONT_LABELS: Record<FontChoice, string> = {
  monospaced: 'Monospaced',
  system: 'System',
  rounded: 'Rounded',
  serif: 'Serif',
};

/** Mirrors `RowAlignment.label`. The labels are directional, the raw values are not. */
export const ALIGNMENT_LABELS: Record<RowAlignment, string> = {
  leading: 'Left',
  center: 'Center',
  trailing: 'Right',
};

/** Mirrors `TextSize.label`. */
export const SIZE_LABELS: Record<TextSize, string> = {
  small: 'Small',
  medium: 'Medium',
  large: 'Large',
  extraLarge: 'Extra Large',
};

export function isFontChoice(value: unknown): value is FontChoice {
  return typeof value === 'string' && (FONT_CHOICES as readonly string[]).includes(value);
}

export function isRowAlignment(value: unknown): value is RowAlignment {
  return typeof value === 'string' && (ROW_ALIGNMENTS as readonly string[]).includes(value);
}

export function isTextSize(value: unknown): value is TextSize {
  return typeof value === 'string' && (TEXT_SIZES as readonly string[]).includes(value);
}
