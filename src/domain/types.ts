/**
 * The TypeScript half of the data contract with the Swift widget.
 *
 * Every string literal in this file is a Swift enum raw value, byte-for-byte.
 * They travel through JSON into `ios/SimplePhoneWidget/Theme.swift`, where Swift's
 * `Codable` matches them by exact string. A single renamed case here (say
 * 'extralarge' instead of 'extraLarge') makes `decodeIfPresent` return the
 * default and the widget silently drifts from the app.
 */

import type { QuoteDuration } from './quotes';

/** Mirrors `FontChoice` in ios/SimplePhoneWidget/Theme.swift. */
export type FontChoice = 'monospaced' | 'system' | 'rounded' | 'serif';

/** Mirrors `RowAlignment` in ios/SimplePhoneWidget/Theme.swift. */
export type RowAlignment = 'leading' | 'center' | 'trailing';

/** Mirrors `TextSize` in ios/SimplePhoneWidget/Theme.swift. `extraLarge` is camelCase in Swift too. */
export type TextSize = 'small' | 'medium' | 'large' | 'extraLarge';

/**
 * The app's ONE language setting. There is no second copy of this value
 * anywhere: it governs the UI strings, the bundled phrases, the language the
 * city search asks Open-Meteo for, and the weekday abbreviations the weather
 * widget renders over in Swift, in another process.
 *
 * A CONCRETE tag, never 'system'. Resolving 'system' would need two independent
 * resolvers — this side picking a phrase catalog, Swift picking weekday names —
 * and they would disagree the instant the phone's language changed, giving
 * Portuguese weekdays over an English phrase. The system locale is read once,
 * on first run, through `matchLanguage`, and stored as one of these.
 */
export type AppLanguage = 'pt-BR' | 'en' | 'es' | 'ja';

/** Mirrors `TemperatureUnit` in ios/SimplePhoneWidget/WeatherSettings.swift. */
export type TemperatureUnit = 'celsius' | 'fahrenheit';

/** Every case, in the order Swift's `CaseIterable` yields them (declaration order). */
export const FONT_CHOICES: readonly FontChoice[] = ['monospaced', 'system', 'rounded', 'serif'];
export const ROW_ALIGNMENTS: readonly RowAlignment[] = ['leading', 'center', 'trailing'];
export const TEXT_SIZES: readonly TextSize[] = ['small', 'medium', 'large', 'extraLarge'];
/**
 * Picker order, and it is user-visible: new languages are APPENDED so an
 * existing user's two rows do not reshuffle under them.
 */
export const APP_LANGUAGES: readonly AppLanguage[] = ['pt-BR', 'en', 'es', 'ja'];
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
/**
 * One line, and optionally who said it.
 *
 * ON THE WIRE this is a bare STRING when there is no author, and an object only
 * when there is. Three reasons, and the third is the one that matters: the 404
 * bundled lines are original and unattributed, so objects would trade 404
 * wrappers for 40 authors; a reader from before this change still finds strings
 * where it expects them; and the stats blob keys counts by TEXT, so identity is
 * unchanged and no counter is orphaned by this migration.
 */
export interface Quote {
  text: string;
  /** Absent, never empty string. The form trims and drops blanks. */
  author?: string;
}

export interface Quotes {
  /** Off means the relay opens the target immediately, as it did before. */
  enabled: boolean;
  duration: QuoteDuration;
  items: Quote[];
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
  /** The one language. Nothing else in memory holds a copy. */
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

// The label tables for FontChoice, RowAlignment, TextSize and TemperatureUnit
// live in src/i18n/ now. They are UI copy, translated per language; this file
// is the wire format, and the raw values above are what Swift decodes.

/**
 * Endonyms. NEVER translated, in any catalog: a user whose phone is in a
 * language this app does not have lands on the English UI and still has to
 * recognise their own language in the picker without reading any English.
 */
export const LANGUAGE_LABELS: Record<AppLanguage, string> = {
  'pt-BR': 'Português',
  en: 'English',
  es: 'Español',
  ja: '日本語',
};

/**
 * The primary subtag of every tag that is not one of the four exact values.
 * pt-PT collapses onto pt-BR because close Portuguese beats English, and every
 * Spanish region (es-419, es-MX, es-ES) shares one neutral catalog.
 */
const BY_PRIMARY_SUBTAG: Record<string, AppLanguage> = {
  en: 'en',
  pt: 'pt-BR',
  es: 'es',
  ja: 'ja',
};

/**
 * A BCP-47 tag from anywhere, collapsed onto the four catalogs that exist.
 *
 * Underscores are normalised because Swift spells regions with one:
 * `Locale.identifier` yields 'pt_BR', and `LauncherConfig.default` seeds its
 * language from `Locale.autoupdatingCurrent.identifier`, so an underscored tag
 * can genuinely reach this from a config the widget side wrote.
 *
 * Anything unmatched lands on English rather than on the app's historical
 * 'pt-BR' default: English is at least readable to more of the people this can
 * happen to, and the picker rows name themselves in their own language.
 */
export function matchLanguage(tag: string): AppLanguage {
  const normalized = tag.replace(/_/g, '-').toLowerCase();
  const exact = APP_LANGUAGES.find((language) => language.toLowerCase() === normalized);
  if (exact !== undefined) return exact;
  return BY_PRIMARY_SUBTAG[normalized.split('-')[0] ?? ''] ?? 'en';
}

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
