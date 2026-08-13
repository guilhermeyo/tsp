/**
 * The read side of the phrase counters.
 *
 * The counters are native-owned state. `ios/SimplePhone/QuoteScreen.swift`
 * writes them under its own App Group key when it draws the line for the next
 * cover, which happens on the backgrounding path only; nothing on this side
 * ever writes them. That is deliberate and is the same separation the weather
 * widget uses for `weather_cache`: one writer per key, so neither side needs a
 * lock and neither can lose the other's data.
 *
 * They are also deliberately NOT in the store. The persistence effect in
 * `LauncherStoreProvider` keys off config identity, so folding these in would
 * push native-owned state back into `launcher_config` and reload the widget for
 * nothing, and `useMemo([config])` would re-render every screen to update a
 * number that one screen uses.
 */
import type { Quote } from './types';
import { LauncherNative } from '../../modules/launcher-native';

/** Missing means the line has never been put up, which reads as blank, not 0. */
export type QuoteCounts = Readonly<Record<string, number | undefined>>;

/**
 * The RAW JSON, not the parsed table, and callers should hold it as state.
 * React bails out of a re-render when the same string is set, so a foreground
 * that changed nothing does not touch a hundred rows.
 *
 * Empty string, never null: it is a state value and `''` parses to `{}`.
 */
export function readQuoteStatsJSON(): string {
  try {
    return LauncherNative.readQuoteStatsJSON() ?? '';
  } catch {
    return '';
  }
}

export function parseQuoteCounts(raw: string): QuoteCounts {
  if (raw === '') return {};

  let parsed: unknown;
  try {
    parsed = JSON.parse(raw);
  } catch {
    return {};
  }
  if (typeof parsed !== 'object' || parsed === null) return {};

  const table = (parsed as { counts?: unknown }).counts;
  if (typeof table !== 'object' || table === null || Array.isArray(table)) return {};

  const counts: Record<string, number> = {};
  for (const [text, value] of Object.entries(table as Record<string, unknown>)) {
    if (typeof value === 'number' && Number.isFinite(value) && value > 0) {
      counts[text] = Math.floor(value);
    }
  }
  return counts;
}

/**
 * The one spread statistic that is legible without jargon, and the exact
 * quantity the native draw minimises: it walks down to zero as the rotation
 * completes a cycle.
 */
export function countNeverShown(items: readonly Quote[], counts: QuoteCounts): number {
  return items.reduce((total, item) => (counts[item.text] === undefined ? total + 1 : total), 0);
}
