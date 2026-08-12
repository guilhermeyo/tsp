import * as Crypto from 'expo-crypto';
import { createContext, useContext, useEffect, useMemo, useReducer, useRef } from 'react';
import type { ReactNode } from 'react';

import { loadConfig, saveConfig } from './configStore';

import type { LauncherApp, LauncherConfig, Theme } from '@/domain/types';

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
}

type Action =
  | { type: 'add'; app: LauncherApp }
  | { type: 'update'; app: LauncherApp }
  | { type: 'removeAt'; index: number }
  | { type: 'removeById'; id: string }
  | { type: 'move'; from: number; to: number }
  | { type: 'updateTheme'; patch: Partial<Theme> };

/**
 * Returning the SAME object reference means "nothing happened". The persistence
 * effect below keys off that identity, so a no-op action must never allocate a
 * new config, or it would write to disk and reload the widget for nothing.
 */
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
  const persisted = useRef(config);

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
