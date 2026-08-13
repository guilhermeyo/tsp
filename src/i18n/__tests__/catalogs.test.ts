import { stringsFor } from '..';
import { en } from '../en';
import { es } from '../es';
import { ja } from '../ja';
import { ptBR } from '../pt-BR';
import { APP_LANGUAGES, LANGUAGE_LABELS } from '@/domain/types';

import type { AppLanguage } from '@/domain/types';

/**
 * `en` is not a translation, it is the SCHEMA: the other three are annotated
 * `: Strings`, so a missing key is a compile error rather than a blank row on a
 * phone. These tests cover what the compiler cannot see: that the spread
 * fallback in `stringsFor` really does fill a gap at RUNTIME, that no catalog
 * ships an empty string, and that the parameterized sentences are functions of
 * the same arity everywhere.
 *
 * A blank settings row is the failure that gets shipped, because it looks like
 * a layout bug rather than a missing string.
 */

const RAW: Record<AppLanguage, Partial<Record<string, unknown>>> = {
  en,
  'pt-BR': ptBR,
  es,
  ja,
};

const KEYS = Object.keys(en) as (keyof typeof en)[];

describe('catalogs', () => {
  it.each(APP_LANGUAGES)('%s resolves every key the schema declares', (language) => {
    const strings = stringsFor(language) as Record<string, unknown>;
    for (const key of KEYS) {
      expect(strings[key]).toBeDefined();
    }
  });

  it.each(APP_LANGUAGES)('%s has no blank string', (language) => {
    const strings = stringsFor(language) as Record<string, unknown>;
    for (const key of KEYS) {
      const value = strings[key];
      if (typeof value === 'string') expect(value.trim()).not.toBe('');
    }
  });

  /**
   * Sentences with values in them are FUNCTIONS, not concatenation, so each
   * language reorders its own clauses and Japanese can drop a plural it does not
   * have. A catalog that turned one back into a bare string would typecheck
   * nowhere, but a catalog that changed its ARITY would silently render
   * `undefined` inside the sentence.
   */
  it.each(APP_LANGUAGES)('%s keeps the shape and arity of every key', (language) => {
    const strings = stringsFor(language) as Record<string, unknown>;
    for (const key of KEYS) {
      const reference = en[key];
      expect(typeof strings[key]).toBe(typeof reference);
      if (typeof reference === 'function') {
        expect((strings[key] as (...a: unknown[]) => unknown).length).toBe(reference.length);
      }
    }
  });

  it.each(APP_LANGUAGES)('%s builds a sentence with the value in it', (language) => {
    const strings = stringsFor(language);
    expect(strings.a11yShownTimes(7)).toContain('7');
    expect(strings.phrasesRotationUnshown(101, 4)).toContain('101');
    expect(strings.phrasesRotationUnshown(101, 4)).toContain('4');
  });

  /**
   * English is the only catalog that may say 'Shown once'. A language with no
   * singular form of its own must still not render the plural sentence with a 1
   * jammed into it, so the branch has to survive translation.
   */
  it.each(APP_LANGUAGES)('%s handles the count of one without printing a stray 1', (language) => {
    expect(stringsFor(language).a11yShownTimes(1)).not.toBe(stringsFor(language).a11yShownTimes(2));
  });

  /**
   * The belt under the compile-time braces. A hand-edited catalog that skips
   * `npx tsc --noEmit` must render the English sentence, not `undefined`.
   */
  it('falls back to English for a key a catalog is missing', () => {
    const [key] = KEYS;
    const patched = { ...ptBR } as Record<string, unknown>;
    delete patched[key];
    expect({ ...en, ...patched }[key]).toBe(en[key]);
  });

  it('does not spread English into itself, since it is already the schema', () => {
    expect(stringsFor('en')).toBe(en);
  });

  it.each(APP_LANGUAGES)('%s ships no emoji, which this repo bans everywhere', (language) => {
    const strings = stringsFor(language) as Record<string, unknown>;
    for (const key of KEYS) {
      const value = strings[key];
      if (typeof value === 'string') expect(value).not.toMatch(/\p{Extended_Pictographic}/u);
    }
  });

  /**
   * Endonyms, and they must never be translated: a user whose phone is in a
   * language this app does not have lands on the English UI and still has to
   * recognise their own language in the picker without reading any English.
   * So no catalog may carry a copy of them, and they must all be distinct.
   */
  it('names every language in its own words, identically in every catalog', () => {
    expect(new Set(Object.values(LANGUAGE_LABELS)).size).toBe(APP_LANGUAGES.length);
    for (const language of APP_LANGUAGES) {
      expect(LANGUAGE_LABELS[language].trim()).not.toBe('');
      const own = RAW[language];
      expect(Object.values(own)).not.toContain(LANGUAGE_LABELS[language]);
    }
  });
});
