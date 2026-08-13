/**
 * The TypeScript half of the data contract with the Swift widget.
 *
 * Every string literal in this file is a Swift enum raw value, byte-for-byte.
 * They travel through JSON into `ios/SimplePhoneWidget/Theme.swift`, where Swift's
 * `Codable` matches them by exact string. A single renamed case here (say
 * 'extralarge' instead of 'extraLarge') makes `decodeIfPresent` return the
 * default and the widget silently drifts from the app.
 */

import type { QuoteDuration, QuoteLanguage } from './quotes';

/** Mirrors `FontChoice` in ios/SimplePhoneWidget/Theme.swift. */
export type FontChoice = 'monospaced' | 'system' | 'rounded' | 'serif';

/** Mirrors `RowAlignment` in ios/SimplePhoneWidget/Theme.swift. */
export type RowAlignment = 'leading' | 'center' | 'trailing';

/** Mirrors `TextSize` in ios/SimplePhoneWidget/Theme.swift. `extraLarge` is camelCase in Swift too. */
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

/** Mirrors `Theme` in ios/SimplePhoneWidget/Theme.swift. */
export interface Theme {
  isDark: boolean;
  font: FontChoice;
  alignment: RowAlignment;
  size: TextSize;
}

/**
 * The interstitial shown while the relay hands off to the target app.
 *
 * `items` is the RESOLVED list, not a language plus a diff. The native relay in
 * AppDelegate.swift picks a line from it before React Native exists, and the
 * cheapest thing to do there is read an array of strings out of the shared
 * config. Keeping the bundled catalog out of Swift is what lets that side stay
 * a dozen lines. The app owns resolution: it seeds `items` on first run and
 * rewrites it when the language changes, preserving anything the user added.
 */
export interface Quotes {
  /** Off means the relay opens the target immediately, as it did before. */
  enabled: boolean;
  language: QuoteLanguage;
  duration: QuoteDuration;
  items: string[];
}

/** The single serialized unit of shared state. Mirrors `LauncherConfig`. */
export interface LauncherConfig {
  apps: LauncherApp[];
  theme: Theme;
  quotes: Quotes;
}

/** Mirrors `Theme.default`. Also the per-field fallback for resilient decoding. */
export const DEFAULT_THEME: Theme = {
  isDark: true,
  font: 'monospaced',
  alignment: 'center',
  size: 'large',
};

/**
 * The first-run default. `items` is deliberately EMPTY here: it is resolved
 * from the bundled catalog at load time, so this constant stays a plain literal
 * and the 200-line catalog is not dragged into every module that wants a
 * fallback theme.
 */
export const DEFAULT_QUOTES: Quotes = {
  enabled: true,
  language: 'pt-BR',
  duration: 'instant',
  items: [],
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
