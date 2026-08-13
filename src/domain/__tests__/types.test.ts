import { APP_LANGUAGES, isAppLanguage, matchLanguage } from '../types';

/**
 * `matchLanguage` decides what a phone shows on its very first launch, from a
 * tag the app does not control. Getting it wrong is not a crash, it is a
 * Brazilian phone opening in English, which reads as the app being broken.
 */
describe('matchLanguage', () => {
  it.each(APP_LANGUAGES)('takes %s exactly', (language) => {
    expect(matchLanguage(language)).toBe(language);
  });

  it.each([
    ['pt-BR', 'pt-BR'],
    ['pt-PT', 'pt-BR'],
    ['pt', 'pt-BR'],
    ['en-US', 'en'],
    ['en-GB', 'en'],
    ['es-419', 'es'],
    ['es-MX', 'es'],
    ['es-ES', 'es'],
    ['ja-JP', 'ja'],
  ] as const)('collapses %s onto %s', (tag, expected) => {
    expect(matchLanguage(tag)).toBe(expected);
  });

  /**
   * Swift spells regions with an underscore: `Locale.identifier` yields 'pt_BR',
   * and the widget process can genuinely write one of these into the config.
   */
  it.each(['pt_BR', 'es_MX', 'ja_JP'])('normalizes the underscore in %s', (tag) => {
    expect(matchLanguage(tag)).toBe(matchLanguage(tag.replace('_', '-')));
  });

  it('is case-insensitive, since a tag can arrive in any case', () => {
    expect(matchLanguage('PT-br')).toBe('pt-BR');
    expect(matchLanguage('JA')).toBe('ja');
  });

  /**
   * English, not the app's historical pt-BR default: it is readable to more of
   * the people this can happen to, and the picker rows name themselves in their
   * own language, so the way out is visible whatever they got.
   */
  it.each(['de', 'fr-FR', 'zh-Hans', '', 'garbage', '-', 'x-y-z'])(
    'falls back to English for %s',
    (tag) => {
      expect(matchLanguage(tag)).toBe('en');
    }
  );

  it('always returns a language the app actually ships', () => {
    for (const tag of ['pt-BR', 'de', 'es_MX', '', 'ja', 'nonsense']) {
      expect(isAppLanguage(matchLanguage(tag))).toBe(true);
    }
  });
});

describe('isAppLanguage', () => {
  it.each(APP_LANGUAGES)('accepts %s', (language) => {
    expect(isAppLanguage(language)).toBe(true);
  });

  it.each([['de'], ['PT-BR'], [''], [null], [undefined], [42], [{}], [['en']]])(
    'rejects %p',
    (value) => {
      expect(isAppLanguage(value)).toBe(false);
    }
  );
});
