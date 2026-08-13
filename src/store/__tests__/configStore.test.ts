import { LauncherNative } from '../../../modules/launcher-native';
import { BUNDLED_QUOTES } from '@/domain/quotes';
import { loadConfig, saveConfig } from '../configStore';

/**
 * The decoder is failure number one on the repo's own list of ways to lose the
 * user's data, and the failure is silent: a config that throws anywhere on the
 * way in resets to defaults, and every app the user added is gone with no error
 * and no crash.
 *
 * So the tests here are almost all malformed input. The shape of the assertion
 * is the same every time and it is the point: a bad FIELD costs that field, and
 * never the apps array.
 */

const read = LauncherNative.readConfigJSON as jest.Mock;
const write = LauncherNative.writeConfigJSON as jest.Mock;

const MINE = { id: 'abc', name: 'WhatsApp', urlString: 'whatsapp-consumer://' };

const stored = (patch: Record<string, unknown>): void => {
  read.mockReturnValue(
    JSON.stringify({ apps: [MINE], language: 'en', quotes: { items: ['keep'] }, ...patch })
  );
};

beforeEach(() => {
  jest.clearAllMocks();
  read.mockReturnValue(null);
});

describe('loadConfig', () => {
  it('seeds the bundled defaults when nothing is stored', () => {
    const config = loadConfig();
    expect(config.apps.length).toBeGreaterThan(0);
    expect(config.quotes.items).toEqual([...BUNDLED_QUOTES.en]);
  });

  it('survives JSON that does not parse', () => {
    read.mockReturnValue('{ not json');
    expect(() => loadConfig()).not.toThrow();
    expect(loadConfig().apps.length).toBeGreaterThan(0);
  });

  it('survives the native side throwing', () => {
    read.mockImplementation(() => {
      throw new Error('no app group');
    });
    expect(() => loadConfig()).not.toThrow();
  });

  it.each([
    ['a top-level array', '[]'],
    ['a bare string', '"hello"'],
    ['null', 'null'],
    ['a number', '42'],
    ['empty', ''],
  ])('survives %s', (_label, raw) => {
    read.mockReturnValue(raw);
    expect(() => loadConfig()).not.toThrow();
  });

  /**
   * The exact shape object bridging produces: a JS `true` arrives as `1`. In
   * Swift this throws `typeMismatch` and takes the whole config down with it.
   * Here it must cost that one field.
   */
  it('keeps the apps when a theme field has the wrong type', () => {
    stored({ theme: { isDark: 1, font: 'comic sans', size: 99 } });
    const config = loadConfig();
    expect(config.apps).toEqual([MINE]);
    expect(typeof config.theme.isDark).toBe('boolean');
    expect(config.theme.font).toBe('monospaced');
  });

  it('keeps the apps when weather is corrupt', () => {
    stored({ weather: { latitude: 'x', longitude: null, unit: 'kelvin' } });
    const config = loadConfig();
    expect(config.apps).toEqual([MINE]);
    expect(config.weather.latitude).toBeNull();
    expect(config.weather.longitude).toBeNull();
  });

  /**
   * Half a coordinate is not a location. Latitude with an implied longitude of
   * zero is a real place in the Atlantic, and it would render a plausible
   * forecast for the wrong hemisphere rather than showing an obvious error.
   */
  it('refuses half a coordinate', () => {
    stored({ weather: { latitude: -26.3, longitude: null, placeName: 'Joinville' } });
    const config = loadConfig();
    expect(config.weather.latitude).toBeNull();
    expect(config.weather.longitude).toBeNull();
  });

  it('takes a whole coordinate', () => {
    stored({ weather: { latitude: -26.3, longitude: -48.85, placeName: 'Joinville' } });
    expect(loadConfig().weather).toMatchObject({ latitude: -26.3, longitude: -48.85 });
  });

  it('drops a row with no name or no url, and keeps the rest', () => {
    stored({ apps: [MINE, { name: 'no url' }, { urlString: 'no-name://' }, 7, null] });
    expect(loadConfig().apps).toEqual([MINE]);
  });

  it('mints an id rather than dropping a row that has none', () => {
    stored({ apps: [{ name: 'Mensagens', urlString: 'ichat://' }] });
    const [app] = loadConfig().apps;
    expect(app).toMatchObject({ name: 'Mensagens', urlString: 'ichat://' });
    expect(app.id.length).toBeGreaterThan(0);
  });

  describe('quotes', () => {
    it('reads a bare string as a line with no author', () => {
      stored({ quotes: { items: ['viver e muito perigoso'] } });
      expect(loadConfig().quotes.items).toEqual([{ text: 'viver e muito perigoso' }]);
    });

    it('reads an object as a line with an author', () => {
      stored({ quotes: { items: [{ text: 'a', author: 'b' }] } });
      expect(loadConfig().quotes.items).toEqual([{ text: 'a', author: 'b' }]);
    });

    /**
     * Absent, never ''. An empty string would render as a dangling en dash under
     * the phrase, and would make every renderer check for two ways to say "no
     * author" instead of one.
     */
    it.each([
      ['an empty author', { text: 'a', author: '' }],
      ['a whitespace author', { text: 'a', author: '   ' }],
      ['a non-string author', { text: 'a', author: 42 }],
    ])('drops %s rather than storing a blank one', (_label, item) => {
      stored({ quotes: { items: [item] } });
      const [quote] = loadConfig().quotes.items;
      expect(quote).toEqual({ text: 'a' });
      expect('author' in quote).toBe(false);
    });

    it('trims both sides', () => {
      stored({ quotes: { items: [{ text: '  a  ', author: '  b  ' }] } });
      expect(loadConfig().quotes.items).toEqual([{ text: 'a', author: 'b' }]);
    });

    it.each([
      ['a blank line', ''],
      ['whitespace only', '   '],
      ['a number', 7],
      ['null', null],
      ['an array', []],
      ['an object with no text', { author: 'b' }],
    ])('drops %s without taking the list down', (_label, item) => {
      stored({ quotes: { items: [item, 'survivor'] } });
      expect(loadConfig().quotes.items).toEqual([{ text: 'survivor' }]);
    });

    /**
     * Empty means never seeded, not "deleted every line". Deleting them all is
     * what the enabled switch is for, and showing nothing would look like a bug.
     */
    it('refills an empty list from the bundle', () => {
      stored({ quotes: { items: [] } });
      expect(loadConfig().quotes.items).toEqual([...BUNDLED_QUOTES.en]);
    });

    it('refills in the config language, not the system one', () => {
      stored({ language: 'ja', quotes: { items: [] } });
      expect(loadConfig().quotes.items).toEqual([...BUNDLED_QUOTES.ja]);
    });

    it('falls back on a duration it does not know', () => {
      stored({ quotes: { items: ['a'], duration: 'eternal' } });
      expect(loadConfig().quotes.duration).toBe('instant');
    });
  });

  describe('language', () => {
    it('prefers the top-level field', () => {
      stored({ language: 'es', quotes: { items: ['a'], language: 'ja' } });
      expect(loadConfig().language).toBe('es');
    });

    /** The entire upgrade path for a config written before the field moved. */
    it('falls back to the old mirror inside quotes', () => {
      read.mockReturnValue(JSON.stringify({ apps: [MINE], quotes: { items: ['a'], language: 'ja' } }));
      expect(loadConfig().language).toBe('ja');
    });

    it('falls back to the system when neither is there', () => {
      (LauncherNative.preferredLanguage as jest.Mock).mockReturnValue('pt-BR');
      read.mockReturnValue(JSON.stringify({ apps: [MINE], quotes: { items: ['a'] } }));
      expect(loadConfig().language).toBe('pt-BR');
    });

    it('rejects a language it does not ship', () => {
      (LauncherNative.preferredLanguage as jest.Mock).mockReturnValue('en-US');
      stored({ language: 'de' });
      expect(loadConfig().language).toBe('en');
    });
  });
});

describe('saveConfig', () => {
  /**
   * Never an object. Object bridging coerces `true` to `1`, Swift's decoder
   * throws on the wrong type, and the whole config resets. A string cannot be
   * coerced on the way across.
   */
  it('hands the native side a string', () => {
    saveConfig(loadConfig());
    expect(write).toHaveBeenCalledTimes(1);
    expect(typeof write.mock.calls[0][0]).toBe('string');
  });

  it('round-trips through the decoder unchanged', () => {
    stored({ language: 'es', quotes: { items: [{ text: 'a', author: 'b' }, 'c'] } });
    const before = loadConfig();
    saveConfig(before);
    read.mockReturnValue(write.mock.calls[0][0] as string);
    expect(loadConfig()).toEqual(before);
  });

  it('writes a line with no author as a bare string', () => {
    stored({ quotes: { items: ['plain'] } });
    saveConfig(loadConfig());
    const parsed = JSON.parse(write.mock.calls[0][0] as string) as {
      quotes: { items: unknown[] };
    };
    expect(parsed.quotes.items).toContain('plain');
  });

  it('reloads the widget, which is a separate process and reads nothing else', () => {
    saveConfig(loadConfig());
    expect(LauncherNative.reloadWidget).toHaveBeenCalled();
  });
});
