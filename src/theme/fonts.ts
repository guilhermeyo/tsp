import { LauncherNative } from '../../modules/launcher-native';

import type { FontChoice } from '@/domain/types';

/**
 * SwiftUI says `.system(size:design:.rounded)` and the OS resolves the concrete
 * face. React Native has no equivalent: `fontFamily` wants a real family name.
 *
 * The accurate path is the native resolver, which asks
 * `UIFontDescriptor.withDesign` for the family the OS would actually use, so
 * the app and the widget render the same letters. These fallbacks are only for
 * the case where the native call returns null, and they are APPROXIMATIONS:
 * Menlo is not SF Mono and New York here is the shipped text face rather than
 * the optical size the system would pick. SF Rounded has no public family name
 * at all, so `rounded` degrades to the plain system font rather than to a
 * wrong-looking substitute.
 *
 * `undefined` means "leave fontFamily unset", which is how RN asks for the
 * system font. That is the correct answer for `system`, and the native resolver
 * deliberately returns null for it.
 */
const FALLBACK_FAMILY: Record<FontChoice, string | undefined> = {
  monospaced: 'Menlo',
  serif: 'New York',
  rounded: undefined,
  system: undefined,
};

// The native call crosses the JSI bridge and allocates a UIFont. It is cheap
// but it runs on every row of a list that re-renders on every theme tap, so
// resolve each design once per process.
const resolved = new Map<FontChoice, string | undefined>();

export function fontFamilyFor(choice: FontChoice): string | undefined {
  const cached = resolved.get(choice);
  if (cached !== undefined || resolved.has(choice)) return cached;

  let family: string | undefined;
  try {
    family = LauncherNative.resolvedFontFamily(choice) ?? FALLBACK_FAMILY[choice];
  } catch {
    // The module is missing (running outside a native build). A wrong-looking
    // font is a far better failure than a crash on the launcher's first render.
    family = FALLBACK_FAMILY[choice];
  }

  resolved.set(choice, family);
  return family;
}
