import * as Crypto from 'expo-crypto';
import { createContext, useContext, useEffect, useMemo, useReducer, useRef } from 'react';
import type { ReactNode } from 'react';

import { consumeQuotesUpgrade, loadConfig, saveConfig } from './configStore';

import { switchLanguageApps } from '@/domain/bundledDefaults';
import { BUNDLED_QUOTES, switchLanguageItems } from '@/domain/quotes';
import type { QuoteDuration } from '@/domain/quotes';
import type {
  AppLanguage,
  LauncherApp,
  LauncherConfig,
  TemperatureUnit,
  Theme,
  WeatherPlace,
  Quote,
} from '@/domain/types';

/**
 * The single source of truth for the whole app, mirroring the one
 * `@StateObject LauncherStore` the SwiftUI version created at launch.
 *
 * There is no second state container anywhere. Screens read `config` and call
 * these methods; nothing else may mutate it.
 */
export interface LauncherStore {
  config: LauncherConfig;
  /** Trims both fields, silently does nothing if either ends up empty, appends to the END. */
  addCustom(name: string, urlString: string): void;
  /** Replaces by id, IN PLACE. Silently does nothing if the id is gone. */
  update(app: LauncherApp): void;
  removeAt(index: number): void;
  removeById(id: string): void;
  move(from: number, to: number): void;
  /** Merges the given fields into the current theme and rebuilds the whole Theme. */
  updateTheme(patch: Partial<Theme>): void;
  setQuotesEnabled(enabled: boolean): void;
  setQuoteDuration(duration: QuoteDuration): void;
  /** Trims, ignores empty, ignores an exact duplicate, appends to the END. */
  /** Author is optional and trimmed away when blank, so `author` is never ''. */
  addQuote(text: string, author?: string): void;
  /** Replaces the line at `index`, keeping its position. Author cleared when blank. */
  updateQuoteAt(index: number, text: string, author?: string): void;
  removeQuoteAt(index: number): void;
  /**
   * The app's one language setting: the UI strings, the bundled phrases, the
   * city search and the widget's weekday names all follow it.
   *
   * Sets `config.language` and reseeds the phrases from the new language's
   * bundle, KEEPING every line the user wrote themselves. That side effect is
   * why the language is never resolved from the phone at read time — see
   * `AppLanguage` in @/domain/types.
   */
  setLanguage(language: AppLanguage): void;
  setWeatherEnabled(enabled: boolean): void;
  /** The three place fields move together; there is no way to set half a location. */
  setWeatherPlace(place: WeatherPlace): void;
  setTemperatureUnit(unit: TemperatureUnit): void;
}

type Action =
  | { type: 'add'; app: LauncherApp }
  | { type: 'update'; app: LauncherApp }
  | { type: 'removeAt'; index: number }
  | { type: 'removeById'; id: string }
  | { type: 'move'; from: number; to: number }
  | { type: 'updateTheme'; patch: Partial<Theme> }
  | { type: 'setQuotesEnabled'; enabled: boolean }
  | { type: 'setQuoteDuration'; duration: QuoteDuration }
  | { type: 'addQuote'; text: string; author?: string }
  | { type: 'updateQuoteAt'; index: number; text: string; author?: string }
  | { type: 'removeQuoteAt'; index: number }
  | { type: 'setLanguage'; language: AppLanguage }
  | { type: 'setWeatherEnabled'; enabled: boolean }
  | { type: 'setWeatherPlace'; place: WeatherPlace }
  | { type: 'setTemperatureUnit'; unit: TemperatureUnit };

/**
 * Returning the SAME object reference means "nothing happened". The persistence
 * effect below keys off that identity, so a no-op action must never allocate a
 * new config, or it would write to disk and reload the widget for nothing.
 */
/** Trims both, drops a blank author, and refuses a blank line. */
function makeQuote(text: string, author?: string): Quote | null {
  const trimmedText = text.trim();
  if (trimmedText === '') return null;
  const trimmedAuthor = author?.trim() ?? '';
  return trimmedAuthor === '' ? { text: trimmedText } : { text: trimmedText, author: trimmedAuthor };
}

function reduce(state: LauncherConfig, action: Action): LauncherConfig {
  switch (action.type) {
    case 'add':
      return { ...state, apps: [...state.apps, action.app] };

    case 'update': {
      const index = state.apps.findIndex((app) => app.id === action.app.id);
      // Swift's `firstIndex(where:)` + assignment. Replacing in place is what
      // preserves LIST POSITION on edit, and list order IS the order the widget
      // renders. A remove-then-append would silently reorder the user's widget
      // every time they fixed a typo.
      if (index === -1) return state;
      const apps = state.apps.slice();
      apps[index] = action.app;
      return { ...state, apps };
    }

    case 'removeAt': {
      if (action.index < 0 || action.index >= state.apps.length) return state;
      const apps = state.apps.slice();
      apps.splice(action.index, 1);
      return { ...state, apps };
    }

    case 'removeById': {
      const apps = state.apps.filter((app) => app.id !== action.id);
      // Swift used `removeAll(where:)`, which drops every match. Ids are unique
      // in practice, so this only differs on a corrupted config.
      if (apps.length === state.apps.length) return state;
      return { ...state, apps };
    }

    case 'move': {
      const { from, to } = action;
      const count = state.apps.length;
      if (from === to) return state;
      if (from < 0 || from >= count || to < 0 || to >= count) return state;
      const apps = state.apps.slice();
      const [moved] = apps.splice(from, 1);
      if (moved === undefined) return state;
      apps.splice(to, 0, moved);
      return { ...state, apps };
    }

    case 'setQuotesEnabled':
      if (state.quotes.enabled === action.enabled) return state;
      return { ...state, quotes: { ...state.quotes, enabled: action.enabled } };

    case 'setLanguage': {
      const { language } = action;
      if (state.language === language) return state;
      return {
        ...state,
        language,
        // The apps move too: a row still carrying its seeded name is a label
        // this app wrote, not something the user typed, and a launcher whose
        // rows do not read the way the home screen reads is a launcher you have
        // to translate in your head. A renamed row is left alone.
        apps: switchLanguageApps(state.language, language, state.apps),
        quotes: {
          ...state.quotes,
          items: switchLanguageItems(state.language, language, state.quotes.items),
        },
      };
    }

    case 'setWeatherEnabled':
      if (state.weather.enabled === action.enabled) return state;
      return { ...state, weather: { ...state.weather, enabled: action.enabled } };

    case 'setWeatherPlace': {
      const { place } = action;
      const { weather } = state;
      if (
        weather.latitude === place.latitude &&
        weather.longitude === place.longitude &&
        weather.placeName === place.placeName
      ) {
        return state;
      }
      return {
        ...state,
        weather: {
          ...weather,
          latitude: place.latitude,
          longitude: place.longitude,
          placeName: place.placeName,
        },
      };
    }

    case 'setTemperatureUnit':
      if (state.weather.unit === action.unit) return state;
      return { ...state, weather: { ...state.weather, unit: action.unit } };

    case 'setQuoteDuration':
      if (state.quotes.duration === action.duration) return state;
      return { ...state, quotes: { ...state.quotes, duration: action.duration } };

    case 'addQuote': {
      const quote = makeQuote(action.text, action.author);
      // Dedupe on TEXT, not on the pair. The same line by two attributions is
      // the same line, and the stats blob keys counts by text, so allowing both
      // would give one counter two rows.
      if (quote === null || state.quotes.items.some((item) => item.text === quote.text)) {
        return state;
      }
      return { ...state, quotes: { ...state.quotes, items: [...state.quotes.items, quote] } };
    }

    case 'updateQuoteAt': {
      const { index } = action;
      if (index < 0 || index >= state.quotes.items.length) return state;
      const quote = makeQuote(action.text, action.author);
      if (quote === null) return state;
      const existing = state.quotes.items[index];
      if (existing !== undefined && existing.text === quote.text && existing.author === quote.author) {
        return state;
      }
      // A rename to text that already exists elsewhere would collide on the
      // stats key, so it is refused rather than silently merging two rows.
      if (state.quotes.items.some((item, i) => i !== index && item.text === quote.text)) {
        return state;
      }
      const items = state.quotes.items.slice();
      items[index] = quote;
      return { ...state, quotes: { ...state.quotes, items } };
    }

    case 'removeQuoteAt': {
      const { index } = action;
      if (index < 0 || index >= state.quotes.items.length) return state;
      const items = state.quotes.items.slice();
      items.splice(index, 1);
      return { ...state, quotes: { ...state.quotes, items } };
    }

    case 'updateTheme':
      // Always a new object, even when the patch changes nothing. Tapping the
      // already-selected font rewrites and reloads in the Swift version too.
      return { ...state, theme: { ...state.theme, ...action.patch } };
  }
}

const LauncherStoreContext = createContext<LauncherStore | null>(null);

export function LauncherStoreProvider({ children }: { children: ReactNode }) {
  // Seeded synchronously through useReducer's lazy initialiser: the native read
  // is a JSI Function, so the first render already has the real config. No
  // async, no loading flag, no empty-list flash — same as `LauncherStore.init`.
  const [config, dispatch] = useReducer(reduce, undefined, loadConfig);

  // What is already on disk. Starts as the value we just read, so mounting
  // never writes anything back.
  // Normally the loaded config IS what is on disk, so mounting writes nothing.
  // The exception is a config that had to be upgraded during load (quotes
  // synthesized from the bundle): that version exists only here until it is
  // written, and the native relay reads the shared container, not this.
  const persisted = useRef<LauncherConfig | null>(consumeQuotesUpgrade() ? null : config);

  useEffect(() => {
    if (persisted.current === config) return;
    persisted.current = config;
    // Every mutation persists immediately: no debounce, no batching, no dirty
    // flag, no explicit Save anywhere in the UI. This is Swift's `persist()` at
    // the end of every mutating method. The one difference is timing — React
    // commits the state and this runs right after, rather than inline — and
    // nothing can observe the gap, because the only reader is the widget and it
    // only redraws when `saveConfig` tells it to.
    saveConfig(config);
  }, [config]);

  const store = useMemo<LauncherStore>(
    () => ({
      config,
      addCustom(name, urlString) {
        const trimmedName = name.trim();
        const trimmedURL = urlString.trim();
        // The form disables its confirm button on the same condition, so this
        // guard is defensive: reachable only if a caller skips the UI.
        if (trimmedName.length === 0 || trimmedURL.length === 0) return;
        dispatch({
          type: 'add',
          app: { id: Crypto.randomUUID(), name: trimmedName, urlString: trimmedURL },
        });
      },
      update(app) {
        dispatch({ type: 'update', app });
      },
      removeAt(index) {
        dispatch({ type: 'removeAt', index });
      },
      removeById(id) {
        dispatch({ type: 'removeById', id });
      },
      move(from, to) {
        // Plain array indices: remove at `from`, insert at `to`. SwiftUI's
        // `move(fromOffsets:toOffset:)` used pre-removal insertion offsets,
        // where dragging down meant `to` was one past the visual target. The
        // reorderable list gives post-move indices directly, so no adjustment.
        dispatch({ type: 'move', from, to });
      },
      updateTheme(patch) {
        dispatch({ type: 'updateTheme', patch });
      },
      setQuotesEnabled(enabled) {
        dispatch({ type: 'setQuotesEnabled', enabled });
      },
      setQuoteDuration(duration) {
        dispatch({ type: 'setQuoteDuration', duration });
      },
      addQuote(text, author) {
        dispatch({ type: 'addQuote', text, author });
      },
      updateQuoteAt(index, text, author) {
        dispatch({ type: 'updateQuoteAt', index, text, author });
      },
      removeQuoteAt(index) {
        dispatch({ type: 'removeQuoteAt', index });
      },
      setLanguage(language) {
        dispatch({ type: 'setLanguage', language });
      },
      setWeatherEnabled(enabled) {
        dispatch({ type: 'setWeatherEnabled', enabled });
      },
      setWeatherPlace(place) {
        dispatch({ type: 'setWeatherPlace', place });
      },
      setTemperatureUnit(unit) {
        dispatch({ type: 'setTemperatureUnit', unit });
      },
    }),
    [config]
  );

  return <LauncherStoreContext.Provider value={store}>{children}</LauncherStoreContext.Provider>;
}

export function useLauncherStore(): LauncherStore {
  const store = useContext(LauncherStoreContext);
  if (store === null) {
    throw new Error('useLauncherStore must be used inside a LauncherStoreProvider');
  }
  return store;
}

/** Convenience for the many screens that only need to style themselves. */
export function useTheme(): Theme {
  return useLauncherStore().config.theme;
}
