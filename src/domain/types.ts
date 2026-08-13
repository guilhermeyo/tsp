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

/**
 * The language of everything the user reads: the bundled phrases here, and the
 * weekday abbreviations the weather widget renders over in Swift.
 *
 * Same two values as `QuoteLanguage` in ./quotes, deliberately restated rather
 * than aliased. Language stopped being a property of the phrase catalog the
 * moment another process started rendering text with it, so it belongs to the
 * config; `quotes.language` survives only as a mirror of this one.
 *
 * A CONCRETE tag, never 'system'. Resolving 'system' would need two independent
 * resolvers — this side picking a phrase catalog, Swift picking weekday names —
 * and they would disagree the instant the phone's language changed, giving
 * Portuguese weekdays over an English phrase. The system locale is read once,
 * on first run, and stored as one of these.
 */
export type AppLanguage = 'pt-BR' | 'en';

/** Mirrors `TemperatureUnit` in ios/SimplePhoneWidget/WeatherSettings.swift. */
export type TemperatureUnit = 'celsius' | 'fahrenheit';

/** Every case, in the order Swift's `CaseIterable` yields them (declaration order). */
export const FONT_CHOICES: readonly FontChoice[] = ['monospaced', 'system', 'rounded', 'serif'];
export const ROW_ALIGNMENTS: readonly RowAlignment[] = ['leading', 'center', 'trailing'];
export const TEXT_SIZES: readonly TextSize[] = ['small', 'medium', 'large', 'extraLarge'];
export const APP_LANGUAGES: readonly AppLanguage[] = ['pt-BR', 'en'];
export const TEMPERATURE_UNITS: readonly TemperatureUnit[] = ['celsius', 'fahrenheit'];

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

/**
 * A place the forecast can be fetched for. The three fields always travel
 * together: coordinates with no name render a nameless column, and a name with
 * no coordinates cannot be fetched.
 */
export interface WeatherPlace {
  latitude: number;
  longitude: number;
  placeName: string;
}

/**
 * Mirrors `WeatherSettings` in ios/SimplePhoneWidget/WeatherSettings.swift.
 *
 * Coordinates are nullable because "no city chosen yet" is a real state that
 * has to survive a round trip through JSON. `null` decodes to Swift's `nil`;
 * an absent key would too, but writing all five fields every time keeps the
 * payload's shape decided in one place (see `serialize`).
 *
 * The unit is a resolved 'celsius' | 'fahrenheit', never 'system', for the same
 * reason `quotes.durationMs` is a resolved number: JS owns the exact bytes and
 * the native side never needs a resolver table.
 */
export interface Weather {
  enabled: boolean;
  latitude: number | null;
  longitude: number | null;
  placeName: string;
  unit: TemperatureUnit;
}

/** The single serialized unit of shared state. Mirrors `LauncherConfig`. */
export interface LauncherConfig {
  apps: LauncherApp[];
  theme: Theme;
  quotes: Quotes;
  weather: Weather;
  /** Authoritative. `quotes.language` is a mirror written by the same reducer case. */
  language: AppLanguage;
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

/**
 * Mirrors `WeatherSettings.default`. Also the per-field fallback for resilient
 * decoding.
 *
 * `enabled` starts true and the place starts EMPTY, which reads backwards until
 * you see the widget: there is no default city here on purpose. A widget that
 * says Sao Paulo to someone in Lisbon is worse than one that asks to be
 * configured, and the widget already knows how to say so. The compiled-in
 * `WeatherSettings.fallbackPlace` on the Swift side is a different thing: it
 * covers the case where the App Group does not share and the widget can see no
 * config at all.
 *
 * `unit` is only the fallback. First run seeds it from the system through
 * `resolveInitialUnit()`.
 */
export const DEFAULT_WEATHER: Weather = {
  enabled: true,
  latitude: null,
  longitude: null,
  placeName: '',
  unit: 'celsius',
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

/** Shown in the language itself, not translated. */
export const LANGUAGE_LABELS: Record<AppLanguage, string> = {
  'pt-BR': 'Português',
  en: 'English',
};

export const TEMPERATURE_UNIT_LABELS: Record<TemperatureUnit, string> = {
  celsius: 'Celsius',
  fahrenheit: 'Fahrenheit',
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

export function isAppLanguage(value: unknown): value is AppLanguage {
  return typeof value === 'string' && (APP_LANGUAGES as readonly string[]).includes(value);
}

export function isTemperatureUnit(value: unknown): value is TemperatureUnit {
  return typeof value === 'string' && (TEMPERATURE_UNITS as readonly string[]).includes(value);
}
