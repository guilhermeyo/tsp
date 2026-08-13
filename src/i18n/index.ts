/**
 * Resolution. A plain object lookup, no library, no `t()`, no runtime key
 * strings, and therefore no call site that can name a key which does not exist.
 */

import { en } from './en';
import { es } from './es';
import { ja } from './ja';
import { ptBR } from './pt-BR';

import type { AppLanguage } from '@/domain/types';

import type { Strings } from './en';

/**
 * The spread is the RUNTIME belt under the compile-time braces, and it is not
 * redundant with the `: Strings` annotation on each catalog.
 *
 * The annotation makes a missing key a build error. The spread makes a missing
 * key that somehow survives, because someone hand-edited a catalog and skipped
 * `npx tsc --noEmit`, render the English sentence instead of rendering
 * `undefined` as a blank row. A blank row in a settings list is the failure that
 * gets shipped, because it looks like a layout bug rather than a missing string.
 *
 * Cost is three object builds at module init and a plain property read per
 * access. `en` is not spread into itself: it is already the whole schema.
 */
const CATALOGS: Record<AppLanguage, Strings> = {
  en,
  'pt-BR': { ...en, ...ptBR },
  es: { ...en, ...es },
  ja: { ...en, ...ja },
};

export function stringsFor(language: AppLanguage): Strings {
  return CATALOGS[language];
}

export type { Strings };
