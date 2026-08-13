import { BUNDLED_QUOTES } from '@/domain/quotes';
import { makeBundledDefaults } from '@/domain/bundledDefaults';
import { loadConfig } from '../configStore';
import { reduce } from '../LauncherStore';

import type { LauncherConfig, Quote } from '@/domain/types';

/**
 * The reducer was the last code here that writes the user's data with nothing
 * around it, and the gap was not theoretical. `switchLanguageItems` and
 * `switchLanguageApps` are the two most carefully tested functions in the
 * project, and none of that reached the ONE line that calls them: inverting
 * their arguments left 241 tests green and the compiler silent while stacking
 * the outgoing catalogue on top of the incoming one on a real phone.
 *
 * A tested function called wrongly is an untested feature. These tests are
 * about the WIRING.
 */

const base = (patch: Partial<LauncherConfig> = {}): LauncherConfig => ({
  ...loadConfig(),
  language: 'en',
  ...patch,
});

const MINE: Quote = { text: 'uma frase que eu escrevi' };

describe('setLanguage', () => {
  it('passes outgoing then incoming, not the other way round', () => {
    const state = base({
      language: 'en',
      quotes: { enabled: true, duration: 'instant', items: [...BUNDLED_QUOTES.en, MINE] },
    });
    const next = reduce(state, { type: 'setLanguage', language: 'ja' });

    expect(next.quotes.items).toHaveLength(BUNDLED_QUOTES.ja.length + 1);
    expect(next.quotes.items).toContainEqual(MINE);
    // The inverted-argument bug: every outgoing line still present.
    for (const gone of BUNDLED_QUOTES.en) {
      if (!BUNDLED_QUOTES.ja.some((q) => q.text === gone.text)) {
        expect(next.quotes.items.map((q) => q.text)).not.toContain(gone.text);
      }
    }
  });

  it('renames the app rows in the same direction', () => {
    const state = base({ language: 'en', apps: makeBundledDefaults('en') });
    const next = reduce(state, { type: 'setLanguage', language: 'pt-BR' });
    expect(next.apps.find((a) => a.urlString === 'ichat://')?.name).toBe('mensagens');
  });

  it('is a no-op for the language already set, so nothing is written', () => {
    const state = base({ language: 'en' });
    expect(reduce(state, { type: 'setLanguage', language: 'en' })).toBe(state);
  });

  it('round-trips', () => {
    const state = base({
      language: 'en',
      apps: makeBundledDefaults('en'),
      quotes: { enabled: true, duration: 'instant', items: [...BUNDLED_QUOTES.en, MINE] },
    });
    const round = reduce(reduce(state, { type: 'setLanguage', language: 'es' }), {
      type: 'setLanguage',
      language: 'en',
    });
    expect(round.quotes.items).toEqual(state.quotes.items);
    expect(round.apps).toEqual(state.apps);
  });
});

/**
 * The defect this file was opened for. The Phrases screen shows the edit form
 * and the per-row delete buttons at the same time, one tap apart.
 */
describe('updateQuote', () => {
  const items: Quote[] = [{ text: 'A' }, { text: 'B' }, { text: 'C' }, { text: 'D' }];
  const withItems = (list: Quote[]): LauncherConfig =>
    base({ quotes: { enabled: true, duration: 'instant', items: list } });

  it('edits the line it was anchored to', () => {
    const next = reduce(withItems(items), { type: 'updateQuote', previousText: 'B', text: 'B2' });
    expect(next.quotes.items.map((q) => q.text)).toEqual(['A', 'B2', 'C', 'D']);
  });

  /**
   * The regression. Start editing B, delete A, then save. Under an index anchor
   * the save landed on C and destroyed it, and the duplicate guard could not
   * catch it because the incoming text was genuinely new.
   */
  it('does not destroy a bystander when a row above was deleted mid-edit', () => {
    const afterDelete = reduce(withItems(items), { type: 'removeQuoteAt', index: 0 });
    const saved = reduce(afterDelete, { type: 'updateQuote', previousText: 'B', text: 'B2' });
    expect(saved.quotes.items.map((q) => q.text)).toEqual(['B2', 'C', 'D']);
    expect(saved.quotes.items.map((q) => q.text)).toContain('C');
  });

  it('drops the edit when the anchored line was the one deleted', () => {
    const afterDelete = reduce(withItems(items), { type: 'removeQuoteAt', index: 1 });
    const saved = reduce(afterDelete, { type: 'updateQuote', previousText: 'B', text: 'B2' });
    // Re-adding it would resurrect a phrase the user just removed.
    expect(saved).toBe(afterDelete);
    expect(saved.quotes.items.map((q) => q.text)).toEqual(['A', 'C', 'D']);
  });

  it('refuses a rename onto another line, which would collide on the stats key', () => {
    const state = withItems(items);
    expect(reduce(state, { type: 'updateQuote', previousText: 'B', text: 'C' })).toBe(state);
  });

  it('allows re-saving a line without changing its text', () => {
    const next = reduce(withItems(items), {
      type: 'updateQuote',
      previousText: 'B',
      text: 'B',
      author: 'Alguém',
    });
    expect(next.quotes.items[1]).toEqual({ text: 'B', author: 'Alguém' });
  });

  it('is a no-op when nothing actually changed', () => {
    const state = withItems(items);
    expect(reduce(state, { type: 'updateQuote', previousText: 'B', text: 'B' })).toBe(state);
  });

  it('refuses a blank line', () => {
    const state = withItems(items);
    expect(reduce(state, { type: 'updateQuote', previousText: 'B', text: '   ' })).toBe(state);
  });
});

/**
 * Returning the SAME object means "nothing happened", and the persistence
 * effect keys off that identity. A no-op that allocates writes to disk and
 * reloads the widget for nothing.
 */
describe('no-op identity', () => {
  it('holds for an out-of-range removal', () => {
    const state = base();
    // Past the end of a 111-line bundle, not merely a large-looking number.
    expect(reduce(state, { type: 'removeQuoteAt', index: state.quotes.items.length })).toBe(state);
    expect(reduce(state, { type: 'removeQuoteAt', index: -1 })).toBe(state);
    expect(reduce(state, { type: 'removeAt', index: -1 })).toBe(state);
  });

  it('holds for an update to an app id that is not there', () => {
    const state = base();
    expect(
      reduce(state, { type: 'update', app: { id: 'nope', name: 'x', urlString: 'y://' } })
    ).toBe(state);
  });
});

describe('move', () => {
  it('reorders, because list order is what the widget renders', () => {
    const state = base({ apps: makeBundledDefaults('en') });
    const next = reduce(state, { type: 'move', from: 0, to: 2 });
    expect(next.apps.map((a) => a.urlString)).toEqual([
      'whatsapp-consumer://',
      'waze://',
      'ichat://',
      'music://',
      'App-Prefs://',
    ]);
  });

  it('keeps every row', () => {
    const state = base({ apps: makeBundledDefaults('en') });
    const next = reduce(state, { type: 'move', from: 4, to: 0 });
    expect(next.apps).toHaveLength(state.apps.length);
    expect(new Set(next.apps.map((a) => a.id))).toEqual(new Set(state.apps.map((a) => a.id)));
  });
});

describe('update', () => {
  /**
   * Replace in place. A remove-then-append would silently reorder the user's
   * widget every time they fixed a typo.
   */
  it('preserves list position when a name is edited', () => {
    const state = base({ apps: makeBundledDefaults('en') });
    const target = state.apps[3];
    const next = reduce(state, { type: 'update', app: { ...target, name: 'renamed' } });
    expect(next.apps[3].name).toBe('renamed');
    expect(next.apps.map((a) => a.urlString)).toEqual(state.apps.map((a) => a.urlString));
  });
});
