/**
 * The phrase shown during the relay.
 *
 * A widget tap always launches this app before the target one, and that gap
 * cannot be removed (see AppDelegate.swift). It can be spent on something,
 * though: one line, held for a beat, between the impulse and the app.
 *
 * WHY THEY ARE SHORT. The line is on screen for about a second and a half while
 * the user is already reaching for something else. Anything longer than a
 * glance is not read, it is skipped, and a skipped line is just a slower
 * launcher. Most of these are under six words on purpose.
 *
 * WHY THEY LIVE IN A .json. They used to be two arrays in this file, on the
 * rule that the native side never carries a catalog. That rule cost the whole
 * feature: on a fresh install the shared container is empty, so the relay had
 * no phrase, so it showed the app list instead. The relay needs a catalog it
 * can reach with no config and no React Native.
 *
 * A .json is the only shape both readers already understand with no build step:
 * TypeScript imports it (`resolveJsonModule` is on in expo/tsconfig.base, and
 * Metro treats .json as a source extension), and the SAME file is copied into
 * the app bundle by the app target's Resources phase, where
 * `QuoteScreen.bundledCatalog` reads it. One file, two readers, no codegen and
 * no duplicated strings.
 */

import type { AppLanguage, Quote } from './types';

import CATALOG from './quotes.json';
// Migration table only — see LEGACY_BUNDLED at the bottom of this file.
import LEGACY_CATALOG from './quotes-legacy.json';

/**
 * How long the phrase is held before the target app is asked to open.
 *
 * A setting rather than a constant because the right value is a matter of
 * taste and of what the phrase is FOR. Treated as a pause it wants to be long;
 * treated as a launcher it wants to be gone. Only the person tapping it forty
 * times a day can say.
 *
 * The felt pause is longer than the number: iOS spends its own moment on the
 * app-to-app transition after this elapses.
 */
export type QuoteDuration = 'instant' | 'quick' | 'short' | 'medium' | 'long';

export const QUOTE_DURATIONS: readonly QuoteDuration[] = [
  'instant',
  'quick',
  'short',
  'medium',
  'long',
];

/**
 * `instant` is zero ADDED delay, not a very small one, and it is the default.
 *
 * The phrase is a cover, not a pause. Its job is that the app list never
 * appears during the handoff, and the handoff already takes a few hundred
 * milliseconds of iOS transition that nothing can shorten. Painting a phrase
 * into exactly that window costs nothing and removes the only thing anyone
 * disliked about the relay.
 *
 * The longer values remain for the other reading of the feature, where the
 * phrase is a deliberate beat of friction between the impulse and the app.
 */
export const QUOTE_DURATION_MS: Record<QuoteDuration, number> = {
  instant: 0,
  quick: 800,
  short: 1500,
  medium: 2600,
  long: 4000,
};

// The duration labels live in src/i18n/ now. Swift never reads them: it reads
// `durationMs`, resolved from the table above at serialize time.

export function isQuoteDuration(value: unknown): value is QuoteDuration {
  return (
    value === 'instant' ||
    value === 'quick' ||
    value === 'short' ||
    value === 'medium' ||
    value === 'long'
  );
}

/**
 * The phrase catalogs, keyed by the app's one language.
 *
 * Written out key by key rather than handed `CATALOG` wholesale so the
 * annotation does the checking: a language added to `AppLanguage` with no array
 * here is a compile error ON THIS LINE, and a typo'd key is one too. No codegen,
 * no runtime assertion, no way for the four catalogs to fall out of step with
 * the four languages.
 *
 * `relay` and `defaultLanguage` are SIBLING keys in the same file, read only by
 * Swift. They are deliberately not mentioned here: Swift's `bundledItems` looks
 * up `bundledCatalog[language]` at the top level, so the phrase arrays have to
 * stay top-level too.
 */
/**
 * Lifts the JSON's dual shape into `Quote`. An entry is a bare STRING when the
 * line has no author, which is all 404 of the original ones, and an object only
 * for the attributed additions. Same rule the config decoder follows, so the
 * bundle and the stored config never disagree about what a quote is.
 */
function lift(entries: readonly (string | { text: string; author?: string })[]): readonly Quote[] {
  return entries.map((entry) =>
    typeof entry === 'string'
      ? { text: entry }
      : entry.author === undefined
        ? { text: entry.text }
        : { text: entry.text, author: entry.author }
  );
}

export const BUNDLED_QUOTES: Record<AppLanguage, readonly Quote[]> = {
  'pt-BR': lift(CATALOG['pt-BR']),
  en: lift(CATALOG.en),
  es: lift(CATALOG.es),
  ja: lift(CATALOG.ja),
};

/**
 * The list to store when the language changes, and the one function in this app
 * that rewrites something the user wrote with no undo.
 *
 * `from` is the OUTGOING language and is the only thing that may be diffed
 * against. Diff against the incoming one and every phrase they typed disappears
 * on the next switch; diff against nothing and the outgoing catalogue piles up
 * on top of the new one. Anything not in the outgoing bundle is theirs, so it
 * survives in its original order, which is also what makes a round trip return
 * exactly the list they started with.
 *
 * Matched on TEXT, never on object identity. A quote used to be a string, and a
 * Set of strings compares by value; adding an optional author made it an object,
 * where a Set compares by reference and a decoded quote is never the same object
 * as the bundled one it was loaded from. That version worked on the first run,
 * when the two really were the same objects, and silently doubled the list on
 * every launch after. Text is also the key the native counters use, so this
 * agrees with them by construction.
 */
export function switchLanguageItems(
  from: AppLanguage,
  to: AppLanguage,
  items: readonly Quote[]
): Quote[] {
  const bundled = new Set(BUNDLED_QUOTES[from].map((quote) => quote.text));
  const written = items.filter((item) => !bundled.has(item.text));
  return [...BUNDLED_QUOTES[to], ...written];
}

/**
 * The catalogue as it shipped BEFORE the cut to twenty attributed lines. Kept
 * for exactly one purpose: telling a phrase the user wrote apart from one the
 * app put there, on a device that still holds the old 111.
 *
 * It is not exported as content and must never be rendered. Swift never sees
 * it either — `quotes.json` stays the shared contract, and this file is a
 * TypeScript-only migration table.
 */
const LEGACY_BUNDLED: Record<AppLanguage, ReadonlySet<string>> = {
  'pt-BR': new Set(LEGACY_CATALOG['pt-BR'].map(textOf)),
  en: new Set(LEGACY_CATALOG.en.map(textOf)),
  es: new Set(LEGACY_CATALOG.es.map(textOf)),
  ja: new Set(LEGACY_CATALOG.ja.map(textOf)),
};

function textOf(entry: string | { text: string }): string {
  return typeof entry === 'string' ? entry : entry.text;
}

/**
 * True when this phrase is one the app supplied, so the UI can refuse to delete
 * it. Matched on TEXT for the same reason `switchLanguageItems` is: a decoded
 * quote is never the same OBJECT as the bundled one it was loaded from.
 *
 * A phrase the user typed that happens to be identical to a bundled line reads
 * as bundled. That is the same collision `switchLanguageItems` already accepts,
 * and the alternative — tagging every stored quote with an origin flag — would
 * change the on-disk shape that Swift also parses.
 */
export function isBundledQuote(language: AppLanguage, text: string): boolean {
  return BUNDLED_QUOTES[language].some((quote) => quote.text === text);
}

/**
 * Brings a stored list up to the current bundled set, keeping every phrase the
 * user wrote. Runs on load, for devices carrying the old 111-line catalogue.
 *
 * IDEMPOTENT BY CONSTRUCTION, which is what makes it safe to run on every load
 * with no "have I migrated?" flag to persist and get wrong. The filter drops
 * anything that is bundled EITHER now or before; whatever survives is the
 * user's, and the current set is prepended whole. Filtering against the legacy
 * list alone would duplicate the ten lines that appear in both, on the second
 * run and every run after — the same shape of bug that once doubled this list
 * on every launch.
 */
export function migrateBundledQuotes(
  language: AppLanguage,
  items: readonly Quote[]
): Quote[] {
  const current = new Set(BUNDLED_QUOTES[language].map((quote) => quote.text));
  const legacy = LEGACY_BUNDLED[language];

  // TRIGGER ON EVIDENCE, not on every load. A line that is in the OLD bundle
  // and not in the current one is proof this device still carries the retired
  // catalogue; without one, there is nothing to migrate and the list is
  // returned untouched.
  //
  // The earlier version prepended the current bundle unconditionally, which
  // rewrote lists that had nothing to do with the migration — including a
  // config holding only phrases the user wrote. Decoding must return what was
  // stored unless there is a concrete reason not to.
  const carriesLegacy = items.some(
    (item) => legacy.has(item.text) && !current.has(item.text)
  );
  if (!carriesLegacy) return items as Quote[];

  // Idempotent by the same test: after this runs there is no legacy-only line
  // left, so a second call returns early above.
  const written = items.filter(
    (item) => !current.has(item.text) && !legacy.has(item.text)
  );
  return [...BUNDLED_QUOTES[language], ...written];
}
