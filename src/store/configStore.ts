import * as Crypto from 'expo-crypto';

import { LauncherNative } from '../../modules/launcher-native';

import { BUNDLED_DEFAULTS } from '@/domain/bundledDefaults';
import { BUNDLED_QUOTES, QUOTE_DURATION_MS, isQuoteDuration, isQuoteLanguage } from '@/domain/quotes';
import {
  DEFAULT_QUOTES,
  DEFAULT_THEME,
  isFontChoice,
  isRowAlignment,
  isTextSize,
  type LauncherApp,
  type LauncherConfig,
  type Quotes,
  type Theme,
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

function defaultConfig(): LauncherConfig {
  return {
    apps: BUNDLED_DEFAULTS.slice(),
    theme: { ...DEFAULT_THEME },
    quotes: { ...DEFAULT_QUOTES, items: BUNDLED_QUOTES[DEFAULT_QUOTES.language].slice() },
  };
}

/**
 * Resilient like `decodeTheme`, and for the same reason: a config written
 * before quotes existed has no `quotes` key at all, and must upgrade in place
 * rather than reset.
 *
 * An EMPTY `items` is treated as "never seeded" and refilled from the bundle,
 * not as "the user deleted every line". Deleting the last phrase is what the
 * `enabled` switch is for, and silently showing nothing would look like a bug.
 */
/**
 * Set when the payload on disk had no usable `quotes` and one had to be
 * synthesized. The store reads it once, on mount, and forces a write.
 *
 * Without this, a config written before this feature existed upgrades only in
 * MEMORY: the app shows a language and a phrase count, while the shared
 * container still has no `quotes` key, so the native relay finds nothing and
 * shows no phrase. It would self-heal the first time the user changed
 * anything, which is exactly the kind of "works after you poke it" bug that
 * reads as broken.
 */
let didSynthesizeQuotes = false;

/** Reads and clears. Only the first caller after a load gets `true`. */
export function consumeQuotesUpgrade(): boolean {
  const value = didSynthesizeQuotes;
  didSynthesizeQuotes = false;
  return value;
}

function decodeQuotes(value: unknown): Quotes {
  if (!isRecord(value)) {
    didSynthesizeQuotes = true;
    return { ...DEFAULT_QUOTES, items: BUNDLED_QUOTES[DEFAULT_QUOTES.language].slice() };
  }
  const language = isQuoteLanguage(value.language) ? value.language : DEFAULT_QUOTES.language;
  const items = Array.isArray(value.items)
    ? value.items.filter((item): item is string => typeof item === 'string' && item.trim() !== '')
    : [];
  return {
    enabled: typeof value.enabled === 'boolean' ? value.enabled : DEFAULT_QUOTES.enabled,
    language,
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
    return defaultConfig();
  }
  if (raw === null || raw.length === 0) return defaultConfig();

  let parsed: unknown;
  try {
    parsed = JSON.parse(raw);
  } catch {
    return defaultConfig();
  }
  if (!isRecord(parsed)) return defaultConfig();

  const apps = decodeApps(parsed.apps);
  // An absent or non-array `apps` is not a config at all. Swift's synthesized
  // decoder fails the same way, and `.default` is what the user then sees.
  if (apps === null) return defaultConfig();

  return { apps, theme: decodeTheme(parsed.theme), quotes: decodeQuotes(parsed.quotes) };
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
    quotes: {
      enabled: config.quotes.enabled,
      language: config.quotes.language,
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
