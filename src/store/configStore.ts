import * as Crypto from 'expo-crypto';

import { LauncherNative } from '../../modules/launcher-native';

import { BUNDLED_DEFAULTS } from '@/domain/bundledDefaults';
import {
  DEFAULT_THEME,
  isFontChoice,
  isRowAlignment,
  isTextSize,
  type LauncherApp,
  type LauncherConfig,
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
  return { apps: BUNDLED_DEFAULTS.slice(), theme: { ...DEFAULT_THEME } };
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

  return { apps, theme: decodeTheme(parsed.theme) };
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
