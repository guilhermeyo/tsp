/**
 * The one way a screen reads a string.
 *
 * Separate from `index.ts` on purpose: the catalogs and the resolver stay free
 * of React and of the store, so they can be read by anything (a test, a script,
 * a future extractor) without dragging a provider along.
 *
 * There is no i18n provider and no re-render plumbing here, and none is needed.
 * `LauncherStore` rebuilds its context value whenever the config changes, so
 * every component that already reads the store re-renders on a language switch,
 * including `ThemedNavigation` in `_layout.tsx` and therefore the header titles.
 */

import { stringsFor } from './index';
import type { Strings } from './en';

import { useLauncherStore } from '@/store/LauncherStore';

export function useStrings(): Strings {
  return stringsFor(useLauncherStore().config.language);
}
