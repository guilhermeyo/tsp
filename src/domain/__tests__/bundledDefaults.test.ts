import { defaultNameFor, makeBundledDefaults, switchLanguageApps } from '../bundledDefaults';
import { APP_LANGUAGES } from '../types';

import type { AppLanguage, LauncherApp } from '../types';

/**
 * The app names are the same class of data as the phrases: this app wrote them,
 * but the user can overwrite them, and once they have, rewriting them is
 * destroying an edit with no undo. So `switchLanguageApps` is held to the same
 * standard as `switchLanguageItems`, and the case that matters most is the one
 * where a row must NOT move.
 */

const PAIRS: [AppLanguage, AppLanguage][] = APP_LANGUAGES.flatMap((from) =>
  APP_LANGUAGES.filter((to) => to !== from).map((to): [AppLanguage, AppLanguage] => [from, to])
);

describe('makeBundledDefaults', () => {
  it.each(APP_LANGUAGES)('seeds %s with names in that language', (language) => {
    for (const app of makeBundledDefaults(language)) {
      expect(app.name).toBe(defaultNameFor(app.urlString, language));
    }
  });

  it.each(APP_LANGUAGES)('%s seeds the same targets in the same order', (language) => {
    expect(makeBundledDefaults(language).map((a) => a.urlString)).toEqual([
      'ichat://',
      'whatsapp-consumer://',
      'waze://',
      'music://',
      'App-Prefs://',
    ]);
  });

  it('mints a fresh id per row', () => {
    const apps = makeBundledDefaults('en');
    expect(new Set(apps.map((a) => a.id)).size).toBe(apps.length);
  });

  /**
   * The plain `whatsapp://` scheme is claimed by BOTH WhatsApp and WhatsApp
   * Business, and iOS picks a winner arbitrarily, which on the test device was
   * Business. Seeding it would reintroduce the bug the consumer scheme fixed.
   */
  it('never seeds the ambiguous whatsapp scheme', () => {
    const urls = makeBundledDefaults('en').map((a) => a.urlString);
    expect(urls).toContain('whatsapp-consumer://');
    expect(urls).not.toContain('whatsapp://');
    expect(urls).not.toContain('whatsapp-smb://');
  });

  /** Messages is the one target where the obvious scheme opens the wrong thing. */
  it('opens Messages, not a compose sheet', () => {
    expect(makeBundledDefaults('en')[0].urlString).toBe('ichat://');
  });

  it.each(APP_LANGUAGES)('%s has no blank name and no duplicate name', (language) => {
    const names = makeBundledDefaults(language).map((a) => a.name);
    for (const name of names) expect(name.trim()).toBe(name);
    for (const name of names) expect(name).not.toBe('');
    expect(new Set(names).size).toBe(names.length);
  });

  /**
   * Precomposed U+00FA, not "u" + U+0301. JSON round-trips either, but they are
   * different strings and only this one matches the Swift literal, so a paste
   * from a decomposing editor would silently desync the two targets.
   */
  it('writes música precomposed', () => {
    const music = makeBundledDefaults('pt-BR').find((a) => a.urlString === 'music://');
    expect(music?.name).toBe('m\u00fasica');
    expect(music?.name).not.toBe('mu\u0301sica');
    expect(music?.name).toHaveLength(6);
  });
});

describe('defaultNameFor', () => {
  it('returns null for a target that is not seeded', () => {
    expect(defaultNameFor('spotify://', 'en')).toBeNull();
  });

  it('keeps the wordmarks identical in every language', () => {
    for (const url of ['whatsapp-consumer://', 'waze://']) {
      const names = APP_LANGUAGES.map((l) => defaultNameFor(url, l));
      expect(new Set(names).size).toBe(1);
    }
  });

  it('translates the Apple apps', () => {
    expect(defaultNameFor('ichat://', 'en')).toBe('messages');
    expect(defaultNameFor('ichat://', 'pt-BR')).toBe('mensagens');
    expect(defaultNameFor('ichat://', 'ja')).toBe('メッセージ');
    expect(defaultNameFor('App-Prefs://', 'es')).toBe('configuración');
  });
});

describe('switchLanguageApps', () => {
  it.each(PAIRS)('%s -> %s renames every untouched row', (from, to) => {
    const next = switchLanguageApps(from, to, makeBundledDefaults(from));
    expect(next.map((a) => a.name)).toEqual(makeBundledDefaults(to).map((a) => a.name));
  });

  it.each(PAIRS)('%s -> %s keeps ids and targets and order', (from, to) => {
    const before = makeBundledDefaults(from);
    const next = switchLanguageApps(from, to, before);
    expect(next.map((a) => a.id)).toEqual(before.map((a) => a.id));
    expect(next.map((a) => a.urlString)).toEqual(before.map((a) => a.urlString));
  });

  it.each(PAIRS)('%s -> %s -> back returns exactly what I started with', (from, to) => {
    const start = makeBundledDefaults(from);
    expect(switchLanguageApps(to, from, switchLanguageApps(from, to, start))).toEqual(start);
  });

  /** The one that matters: a rename is the user's, and it must survive. */
  it('never touches a row the user renamed', () => {
    const apps = makeBundledDefaults('en').map((app) =>
      app.urlString === 'whatsapp-consumer://' ? { ...app, name: 'zap' } : app
    );
    const next = switchLanguageApps('en', 'ja', apps);
    expect(next.find((a) => a.urlString === 'whatsapp-consumer://')?.name).toBe('zap');
    expect(next.find((a) => a.urlString === 'ichat://')?.name).toBe('メッセージ');
  });

  it('leaves a row renamed to another language’s default alone', () => {
    const apps: LauncherApp[] = [{ id: '1', name: 'mensagens', urlString: 'ichat://' }];
    expect(switchLanguageApps('en', 'ja', apps)[0].name).toBe('mensagens');
  });

  it('leaves an app the user added alone', () => {
    const apps: LauncherApp[] = [{ id: '1', name: 'spotify', urlString: 'spotify://' }];
    expect(switchLanguageApps('en', 'ja', apps)).toEqual(apps);
  });

  it('is case-sensitive, since a rename to Messages is still a rename', () => {
    const apps: LauncherApp[] = [{ id: '1', name: 'Messages', urlString: 'ichat://' }];
    expect(switchLanguageApps('en', 'pt-BR', apps)[0].name).toBe('Messages');
  });

  it('survives an empty list', () => {
    expect(switchLanguageApps('en', 'ja', [])).toEqual([]);
  });

  /**
   * The reducer's persistence effect keys off object identity, so a row whose
   * name does not actually change must come back as the SAME object or every
   * language switch writes rows that did not move.
   */
  it('returns the same object for a name that does not change', () => {
    const apps = makeBundledDefaults('pt-BR');
    const next = switchLanguageApps('pt-BR', 'es', apps);
    const waze = apps.findIndex((a) => a.urlString === 'waze://');
    expect(next[waze]).toBe(apps[waze]);
  });
});
