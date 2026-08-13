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

import CATALOG from './quotes.json';

export type QuoteLanguage = 'pt-BR' | 'en';

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

export const QUOTE_DURATION_LABEL: Record<QuoteDuration, string> = {
  instant: 'Instant',
  quick: 'Quick',
  short: 'Short',
  medium: 'Medium',
  long: 'Long',
};

export function isQuoteDuration(value: unknown): value is QuoteDuration {
  return (
    value === 'instant' ||
    value === 'quick' ||
    value === 'short' ||
    value === 'medium' ||
    value === 'long'
  );
}

export const QUOTE_LANGUAGES: readonly QuoteLanguage[] = ['pt-BR', 'en'];

export function isQuoteLanguage(value: unknown): value is QuoteLanguage {
  return value === 'pt-BR' || value === 'en';
}

/** Label for the language picker. Shown in the user's own language, not translated. */
export const QUOTE_LANGUAGE_LABEL: Record<QuoteLanguage, string> = {
  'pt-BR': 'Português',
  en: 'English',
};

export const BUNDLED_QUOTES: Record<QuoteLanguage, readonly string[]> = {
  'pt-BR': CATALOG['pt-BR'],
  en: CATALOG.en,
};
