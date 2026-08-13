import * as Crypto from 'expo-crypto';

import { LauncherNative } from '../../modules/launcher-native';

import { BUNDLED_DEFAULTS } from '@/domain/bundledDefaults';
import { BUNDLED_QUOTES, QUOTE_DURATION_MS, isQuoteDuration } from '@/domain/quotes';
import {
  DEFAULT_QUOTES,
  DEFAULT_THEME,
  DEFAULT_WEATHER,
  isAppLanguage,
  isFontChoice,
  isRowAlignment,
  isTemperatureUnit,
  isTextSize,
  matchLanguage,
  type AppLanguage,
  type LauncherApp,
  type LauncherConfig,
  type Quotes,
  type TemperatureUnit,
  type Theme,
  type Weather,
} from '@/domain/types';

/**
 * The read/write half of the data contract. Mirrors `ConfigStore.swift`, which
 * still exists on the widget side and reads whatever this file writes.
 *
 * THE ONE RULE: config crosses the bridge as a JSON STRING that JavaScript
 * built itself. Never hand the native side an object to serialize. Object
 * bridging round-trips through JSONSerialization, which can turn `isDark: true`
 * into `1`. Swift's `decodeIfPresent(Bool.self, ...)` THROWS `typeMismatch` on a
 * number (it returns nil only for an absent or null key), the throw escapes
 * Theme's resilient init, `ConfigStore`'s `try?` swallows it, and the entire
 * config resets to `.default`. The user loses every app and nothing anywhere
 * reports an error. JS owns the bytes.
 */

/**
 * The system language, collapsed onto the four catalogs this app actually has.
 *
 * Read from the phone ONCE and stored as a concrete tag, which is the whole
 * design of `config.language`: a stored 'system' would have to be resolved
 * independently here and in Swift, and the two resolvers would disagree the
 * moment the phone's language changed. It would also mean a phone-language
 * change silently rewrote the phrase catalog the user is looking at, since
 * that is what `setLanguage` does.
 *
 * `matchLanguage` owns the collapsing rule, so this side and anything else that
 * has to turn a tag into a setting agree by construction.
 *
 * Native call, so it is wrapped: `LauncherNative` is a JSI function and a
 * throw here would take the whole first render with it.
 */
export function resolveInitialLanguage(): AppLanguage {
  try {
    return matchLanguage(LauncherNative.preferredLanguage());
  } catch {
    return 'en';
  }
}

/** Same shape, same reasoning, for the temperature unit. */
export function resolveInitialUnit(): TemperatureUnit {
  try {
    return LauncherNative.prefersMetric() ? 'celsius' : 'fahrenheit';
  } catch {
    return 'celsius';
  }
}

function defaultConfig(): LauncherConfig {
  // One native read feeding the one field. Calling the resolver twice would be
  // harmless today and a bug the day it stops being deterministic.
  const language = resolveInitialLanguage();
  return {
    apps: BUNDLED_DEFAULTS.slice(),
    theme: { ...DEFAULT_THEME },
    quotes: { ...DEFAULT_QUOTES, items: BUNDLED_QUOTES[language].slice() },
    weather: { ...DEFAULT_WEATHER, unit: resolveInitialUnit() },
    language,
  };
}

/**
 * Set when the payload on disk was missing something that had to be
 * synthesized: `quotes` (the original case), and now `language` or `weather`
 * too. The store reads it once, on mount, and forces a write.
 *
 * Without this, a config written before a feature existed upgrades only in
 * MEMORY: the app shows a language and a phrase count, while the shared
 * container still has no `quotes` key, so the native relay finds nothing and
 * shows no phrase. It would self-heal the first time the user changed
 * anything, which is exactly the kind of "works after you poke it" bug that
 * reads as broken. The weather widget makes it worse, not better: it renders in
 * another process that never runs any of this code, so a language it cannot see
 * is a language it never gets.
 *
 * The name is historical. It means "the config was upgraded during load".
 */
let didSynthesizeQuotes = false;

/**
 * Every "there is nothing usable on disk" exit of `loadConfig`.
 *
 * These used to return `defaultConfig()` directly, which meant a fresh install
 * held a perfectly good config in memory and wrote NOTHING to the shared
 * container until the user happened to edit something. The App Group stayed
 * empty, the widget rendered `BundledDefaults`, and the native relay found no
 * phrase. Marking the synthesis here is what makes the provider write the seed
 * on mount.
 */
function synthesizedConfig(): LauncherConfig {
  didSynthesizeQuotes = true;
  return defaultConfig();
}

/** Reads and clears. Only the first caller after a load gets `true`. */
export function consumeQuotesUpgrade(): boolean {
  const value = didSynthesizeQuotes;
  didSynthesizeQuotes = false;
  return value;
}

/**
 * Resilient like `decodeTheme`, and for the same reason: a config written
 * before quotes existed has no `quotes` key at all, and must upgrade in place
 * rather than reset.
 *
 * An EMPTY `items` is treated as "never seeded" and refilled from the bundle,
 * not as "the user deleted every line". Deleting the last phrase is what the
 * `enabled` switch is for, and silently showing nothing would look like a bug.
 *
 * `language` is a PARAMETER and is never written into the result. `quotes` no
 * longer carries a language at all: `config.language` is the only copy in
 * memory. It still has to be passed in, because it is what selects the bundle
 * an empty `items` is refilled from, and reading it out of `value` here would
 * reintroduce exactly the second source of truth this removed.
 */
function decodeQuotes(value: unknown, language: AppLanguage): Quotes {
  if (!isRecord(value)) {
    didSynthesizeQuotes = true;
    return { ...DEFAULT_QUOTES, items: BUNDLED_QUOTES[language].slice() };
  }
  const items = Array.isArray(value.items)
    ? value.items.filter((item): item is string => typeof item === 'string' && item.trim() !== '')
    : [];
  return {
    enabled: typeof value.enabled === 'boolean' ? value.enabled : DEFAULT_QUOTES.enabled,
    duration: isQuoteDuration(value.duration) ? value.duration : DEFAULT_QUOTES.duration,
    items: items.length > 0 ? items : ((didSynthesizeQuotes = true), BUNDLED_QUOTES[language].slice()),
  };
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}

/**
 * Mirrors `Theme.init(from decoder:)`: each field is taken only when it is
 * present AND valid, otherwise it falls back to the default. Older configs
 * written before `alignment` and `size` existed still decode.
 *
 * ONE DELIBERATE DIVERGENCE, in the safer direction: Swift throws on a
 * WRONG-TYPED field (the `1`-instead-of-true case above) and loses the whole
 * config, apps included. Here a bad theme field only costs that field. The apps
 * array is never discarded because of the theme.
 */
function decodeTheme(value: unknown): Theme {
  if (!isRecord(value)) return { ...DEFAULT_THEME };
  return {
    isDark: typeof value.isDark === 'boolean' ? value.isDark : DEFAULT_THEME.isDark,
    font: isFontChoice(value.font) ? value.font : DEFAULT_THEME.font,
    alignment: isRowAlignment(value.alignment) ? value.alignment : DEFAULT_THEME.alignment,
    size: isTextSize(value.size) ? value.size : DEFAULT_THEME.size,
  };
}

/**
 * Where the language comes from, in order of authority.
 *
 *  1. `config.language`, the field this app writes.
 *  2. `quotes.language`, where the value lived before the weather widget made
 *     it a property of the whole config. Every config already on a device has
 *     this and not the first, so reading it is the entire upgrade path.
 *  3. the system, for a config that predates both.
 *
 * Cases 2 and 3 mark the config upgraded, which forces a write on mount. That
 * write is what puts `language` in the shared container, and the widget is a
 * separate process that reads nothing else.
 */
function decodeLanguage(parsed: Record<string, unknown>): AppLanguage {
  if (isAppLanguage(parsed.language)) return parsed.language;

  didSynthesizeQuotes = true;

  // Purely a READ path now. Nothing in this app has held a `quotes.language` in
  // memory since the mirror was deleted; this branch exists only for configs
  // already sitting on a device, and the write below re-lands the value at the
  // top level, after which it is never reached again for that install.
  const quotes = parsed.quotes;
  if (isRecord(quotes) && isAppLanguage(quotes.language)) return quotes.language;

  return resolveInitialLanguage();
}

function finiteNumber(value: unknown): number | null {
  return typeof value === 'number' && Number.isFinite(value) ? value : null;
}

/**
 * Resilient in exactly the way `decodeTheme` is: a bad field costs that field
 * and nothing else. The apps array is never at risk from anything in here.
 *
 * The coordinates are decoded as a PAIR. Half a coordinate is not a location,
 * and letting one through would mean a fetch against latitude with an implied
 * longitude of zero, which is a real place in the Atlantic and would render a
 * plausible-looking forecast for the wrong hemisphere.
 *
 * A missing `weather` object seeds the unit from the system, the same way first
 * run does. Everyone who already has this app installed reaches this branch
 * exactly once, and Celsius for someone in the United States would be a worse
 * first impression than one native call.
 */
function decodeWeather(value: unknown): Weather {
  if (!isRecord(value)) {
    didSynthesizeQuotes = true;
    return { ...DEFAULT_WEATHER, unit: resolveInitialUnit() };
  }

  const latitude = finiteNumber(value.latitude);
  const longitude = finiteNumber(value.longitude);
  const hasPlace = latitude !== null && longitude !== null;

  return {
    enabled: typeof value.enabled === 'boolean' ? value.enabled : DEFAULT_WEATHER.enabled,
    latitude: hasPlace ? latitude : null,
    longitude: hasPlace ? longitude : null,
    placeName: typeof value.placeName === 'string' ? value.placeName : DEFAULT_WEATHER.placeName,
    // Not `resolveInitialUnit()`: the object exists, so the user already had a
    // unit and only this field is corrupt. Asking the system now would override
    // a deliberate choice with a regional guess.
    unit: isTemperatureUnit(value.unit) ? value.unit : DEFAULT_WEATHER.unit,
  };
}

/**
 * A row survives if it has a usable name and url. A missing or non-string id
 * gets a fresh one rather than dropping the row: the id is bookkeeping, the
 * name and url are the user's data.
 */
function decodeApps(value: unknown): LauncherApp[] | null {
  if (!Array.isArray(value)) return null;
  const apps: LauncherApp[] = [];
  for (const item of value) {
    if (!isRecord(item)) continue;
    if (typeof item.name !== 'string' || typeof item.urlString !== 'string') continue;
    apps.push({
      id: typeof item.id === 'string' && item.id.length > 0 ? item.id : Crypto.randomUUID(),
      name: item.name,
      urlString: item.urlString,
    });
  }
  return apps;
}

/**
 * Synchronous by design. The native functions are Expo `Function`s, which run
 * over JSI on the calling thread, so the store can be seeded during the first
 * render with no loading state, no splash and no flash of an empty list —
 * matching `LauncherStore.init`'s synchronous `ConfigStore.load()`.
 */
export function loadConfig(): LauncherConfig {
  let raw: string | null = null;
  try {
    raw = LauncherNative.readConfigJSON();
  } catch {
    return synthesizedConfig();
  }
  if (raw === null || raw.length === 0) return synthesizedConfig();

  let parsed: unknown;
  try {
    parsed = JSON.parse(raw);
  } catch {
    return synthesizedConfig();
  }
  if (!isRecord(parsed)) return synthesizedConfig();

  const apps = decodeApps(parsed.apps);
  // An absent or non-array `apps` is not a config at all. Swift's synthesized
  // decoder fails the same way, and `.default` is what the user then sees.
  if (apps === null) return synthesizedConfig();

  const language = decodeLanguage(parsed);
  return {
    apps,
    theme: decodeTheme(parsed.theme),
    quotes: decodeQuotes(parsed.quotes, language),
    weather: decodeWeather(parsed.weather),
    language,
  };
}

/**
 * Project explicitly onto the contract keys instead of stringifying whatever
 * the object happens to carry. Swift ignores unknown keys, so a stray field
 * would not break decoding, but the payload is read by another process and its
 * shape should be decided here, in one place.
 */
function serialize(config: LauncherConfig): string {
  return JSON.stringify({
    apps: config.apps.map((app) => ({
      id: app.id,
      name: app.name,
      urlString: app.urlString,
    })),
    // Top-level and authoritative. The widget reads THIS one to pick weekday
    // names.
    language: config.language,
    quotes: {
      enabled: config.quotes.enabled,
      // A WIRE ECHO, not a stored mirror: there is no `quotes.language` in
      // memory any more, so this is projected from the single source at write
      // time and cannot disagree with it. It is here because a reader that
      // still expects it can outlive this build — most concretely an older
      // binary side-loaded from Xcode onto the same device after testing this
      // one, which would otherwise find no language and fall back. Costs one
      // line and is the only part of killing the mirror that could lose data.
      // DELETE in a later release, once no such binary is in circulation.
      language: config.language,
      duration: config.quotes.duration,
      // Resolved here so the native side never needs the label table. It reads
      // a number and sleeps; a Swift copy of these four values would be one
      // more pair to keep in sync for nothing.
      durationMs: QUOTE_DURATION_MS[config.quotes.duration],
      items: config.quotes.items,
    },
    theme: {
      isDark: config.theme.isDark,
      font: config.theme.font,
      alignment: config.theme.alignment,
      size: config.theme.size,
    },
    // All five fields, every time, including nulls. Swift's `WeatherSettings`
    // treats an absent key and a null key identically, so this is not a
    // correctness requirement — it is so the payload on disk always has the
    // shape described here rather than a shape that depends on what the user
    // has configured so far.
    weather: {
      enabled: config.weather.enabled,
      latitude: config.weather.latitude,
      longitude: config.weather.longitude,
      placeName: config.weather.placeName,
      unit: config.weather.unit,
    },
  });
}

/**
 * Write, then reload the widget — always both, always together.
 *
 * The widget's timeline policy is `.never`: it schedules zero refreshes of its
 * own, so `reloadWidget()` is the ONLY thing that ever makes it redraw. Drop
 * the reload and the widget appears frozen after every edit.
 */
export function saveConfig(config: LauncherConfig): void {
  try {
    LauncherNative.writeConfigJSON(serialize(config));
  } catch (error) {
    // Swift swallowed encode failures too (`try?`). A failed write means the
    // widget keeps its previous contents; the app's in-memory state is already
    // updated, so the user sees their edit and the widget disagrees.
    console.warn('[configStore] failed to persist launcher config', error);
  }
  try {
    LauncherNative.reloadWidget();
  } catch (error) {
    console.warn('[configStore] failed to reload widget timelines', error);
  }
}
