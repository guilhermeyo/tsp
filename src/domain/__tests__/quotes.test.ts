import { BUNDLED_QUOTES, switchLanguageItems } from '../quotes';
import { APP_LANGUAGES } from '../types';

import type { AppLanguage, Quote } from '../types';

/**
 * `switchLanguageItems` is the only code in the app that rewrites a list the
 * user wrote, in place, with no undo. Everything else here is a convenience.
 *
 * The three ways it can be wrong all produce a plausible-looking list, which is
 * why they are asserted separately rather than through one big snapshot:
 * diffing against the INCOMING catalogue deletes every phrase the user typed;
 * diffing against nothing leaves the outgoing catalogue stacked on top of the
 * new one; and comparing by REFERENCE silently degrades into the second case
 * the moment the list has been through a save/load cycle, because a decoded
 * quote is never the same object as the bundled one it came from.
 */

/** A load from disk: same values, new objects. This is the normal case. */
const asDecoded = (items: readonly Quote[]): Quote[] =>
  items.map((item) => (item.author === undefined ? { text: item.text } : { ...item }));

const PAIRS: [AppLanguage, AppLanguage][] = APP_LANGUAGES.flatMap((from) =>
  APP_LANGUAGES.filter((to) => to !== from).map((to): [AppLanguage, AppLanguage] => [from, to])
);

describe('switchLanguageItems', () => {
  const MINE: Quote[] = [
    { text: 'uma frase que eu escrevi' },
    { text: 'outra minha', author: 'Guilherme' },
  ];

  it.each(PAIRS)('%s -> %s keeps exactly the bundled set plus what I wrote', (from, to) => {
    const items = [...asDecoded(BUNDLED_QUOTES[from]), ...MINE];
    const next = switchLanguageItems(from, to, items);

    const incoming = BUNDLED_QUOTES[to].map((q) => q.text);
    const outgoingOnly = BUNDLED_QUOTES[from]
      .map((q) => q.text)
      .filter((text) => !incoming.includes(text));

    expect(next.map((q) => q.text)).toEqual([...incoming, ...MINE.map((q) => q.text)]);
    expect(next).toHaveLength(BUNDLED_QUOTES[to].length + MINE.length);
    for (const stale of outgoingOnly) {
      expect(next.map((q) => q.text)).not.toContain(stale);
    }
  });

  it.each(PAIRS)('%s -> %s -> back returns the list I started with', (from, to) => {
    const start = [...asDecoded(BUNDLED_QUOTES[from]), ...MINE];
    const round = switchLanguageItems(to, from, switchLanguageItems(from, to, start));
    expect(round).toEqual(start);
  });

  it('never duplicates a line', () => {
    const items = [...asDecoded(BUNDLED_QUOTES['pt-BR']), ...MINE];
    const next = switchLanguageItems('pt-BR', 'en', items);
    const texts = next.map((q) => q.text);
    expect(new Set(texts).size).toBe(texts.length);
  });

  it('keeps the author on a line I wrote', () => {
    const next = switchLanguageItems('en', 'ja', [...asDecoded(BUNDLED_QUOTES.en), ...MINE]);
    expect(next).toContainEqual({ text: 'outra minha', author: 'Guilherme' });
  });

  it('survives a list holding nothing bundled at all', () => {
    expect(switchLanguageItems('en', 'es', MINE)).toEqual([...BUNDLED_QUOTES.es, ...MINE]);
  });

  it('survives an empty list', () => {
    expect(switchLanguageItems('en', 'es', [])).toEqual([...BUNDLED_QUOTES.es]);
  });

  /**
   * The specific regression: adding an optional author turned quotes from
   * strings into objects, and a Set of objects matches by identity. Reference
   * comparison passes every test above as long as the fixture reuses the
   * bundled objects, and fails the moment the list has been decoded, which is
   * every launch after the first.
   */
  it('matches decoded quotes, not just the bundled object references', () => {
    const fresh = switchLanguageItems('en', 'es', [...BUNDLED_QUOTES.en]);
    const decoded = switchLanguageItems('en', 'es', asDecoded(BUNDLED_QUOTES.en));
    expect(decoded).toEqual(fresh);
    expect(decoded).toHaveLength(BUNDLED_QUOTES.es.length);
  });
});

describe('BUNDLED_QUOTES', () => {
  it.each(APP_LANGUAGES)('%s has no duplicate text', (language) => {
    const texts = BUNDLED_QUOTES[language].map((q) => q.text);
    expect(new Set(texts).size).toBe(texts.length);
  });

  it.each(APP_LANGUAGES)('%s has no blank line and no blank author', (language) => {
    for (const quote of BUNDLED_QUOTES[language]) {
      expect(quote.text.trim()).toBe(quote.text);
      expect(quote.text).not.toBe('');
      // Absent, never empty: an empty string would render a dangling dash.
      expect(quote.author).not.toBe('');
      if ('author' in quote) expect(typeof quote.author).toBe('string');
    }
  });

  it('every language ships the same number of lines', () => {
    const sizes = APP_LANGUAGES.map((l) => BUNDLED_QUOTES[l].length);
    expect(new Set(sizes).size).toBe(1);
  });

  /**
   * The ceiling is layout, not taste: 32pt insets and a 30pt font on the
   * narrowest current iPhone leaves 311pt, and an ideograph advances a full em.
   */
  it('japanese lines fit the cover at one em per character', () => {
    for (const quote of BUNDLED_QUOTES.ja) {
      expect(quote.text.length).toBeLessThanOrEqual(12);
    }
  });
});
