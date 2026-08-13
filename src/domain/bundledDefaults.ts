import * as Crypto from 'expo-crypto';

import type { LauncherApp } from './types';

/**
 * The first-run seed, mirroring `ios/SimplePhoneWidget/BundledDefaults.swift`.
 *
 * The two copies must stay in sync for a non-obvious reason: the widget renders
 * THIS list, compiled in, whenever it cannot read the App Group suite (free
 * Apple team, or a signing setup where the entitlement is unavailable). On such
 * a device the app looks fine and the widget is frozen on these five names.
 *
 * Names are the user's own pt-BR lowercase labels and are content, not UI
 * strings. Do not translate them.
 *
 * "música" carries U+00FA (precomposed LATIN SMALL LETTER U WITH ACUTE), not
 * "u" + U+0301. JSON round-trips either, but the two are different strings and
 * only the precomposed form matches the Swift literal.
 */
const SEEDS: readonly Omit<LauncherApp, 'id'>[] = [
  { name: 'mensagens', urlString: 'messages://' },
  { name: 'whatsapp', urlString: 'whatsapp://' },
  { name: 'waze', urlString: 'waze://' },
  { name: 'música', urlString: 'music://' },
  // App-Prefs:// is a private URL scheme. It works today, but it is a
  // documented App Store guideline 2.5.1 rejection trigger and must be removed
  // before any submission. It survives here because this is a sideloaded app.
  { name: 'ajustes', urlString: 'App-Prefs://' },
];

/** Fresh seeds with newly minted ids, mirroring Swift's `LauncherApp(name:urlString:)`. */
export function makeBundledDefaults(): LauncherApp[] {
  return SEEDS.map((seed) => ({ id: Crypto.randomUUID(), ...seed }));
}

/**
 * Ids are minted once per app launch, and only persisted if this list is ever
 * actually saved (first run, or recovery from unreadable config). That mirrors
 * Swift, where `BundledDefaults.apps` is a `static let` whose UUIDs are created
 * when the type is first touched.
 */
export const BUNDLED_DEFAULTS: LauncherApp[] = makeBundledDefaults();
