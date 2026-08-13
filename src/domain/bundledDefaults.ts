import * as Crypto from 'expo-crypto';

import type { AppLanguage, LauncherApp } from './types';

/**
 * The first-run seed, mirroring `ios/SimplePhoneWidget/BundledDefaults.swift`.
 *
 * Names are LOCALIZED, and the names chosen are the ones Apple itself uses for
 * those apps in each language. This is a launcher: a row that does not read the
 * way the icon on the home screen reads is a row the user has to translate in
 * their head every time. WhatsApp and Waze are wordmarks and are the same
 * everywhere, which is why they look untranslated.
 *
 * Lowercase throughout, which is the original Swift app's house style and the
 * one thing here that is taste rather than accuracy.
 *
 * "música" carries U+00FA (precomposed LATIN SMALL LETTER U WITH ACUTE), not
 * "u" + U+0301. JSON round-trips either, but the two are different strings and
 * only the precomposed form matches the Swift literal.
 */
interface Seed {
  readonly urlString: string;
  readonly names: Readonly<Record<AppLanguage, string>>;
}

const SEEDS: readonly Seed[] = [
  // ichat://, not sms:// or messages://. Tested on an iPhone 17 Pro running
  // iOS 26.6: sms:// and messages:// both open the COMPOSE sheet with an empty
  // To: field, while ichat:// opens Messages itself, restored to whatever the
  // user was last looking at. Undocumented, and the only one that behaves like
  // a launcher row should. The simulator disagrees, so do not "fix" this from
  // simulator evidence.
  {
    urlString: 'ichat://',
    names: { en: 'messages', 'pt-BR': 'mensagens', es: 'mensajes', ja: 'メッセージ' },
  },
  // whatsapp-consumer://, not whatsapp://. The plain scheme is claimed by BOTH
  // WhatsApp and WhatsApp Business, and iOS resolves the collision by picking
  // one, which on this device was Business. The two variants publish distinct
  // schemes for exactly this.
  {
    urlString: 'whatsapp-consumer://',
    names: { en: 'whatsapp', 'pt-BR': 'whatsapp', es: 'whatsapp', ja: 'whatsapp' },
  },
  {
    urlString: 'waze://',
    names: { en: 'waze', 'pt-BR': 'waze', es: 'waze', ja: 'waze' },
  },
  {
    urlString: 'music://',
    names: { en: 'music', 'pt-BR': 'música', es: 'música', ja: 'ミュージック' },
  },
  // App-Prefs:// is a private URL scheme. It works today, but it is a
  // documented App Store guideline 2.5.1 rejection trigger and must be removed
  // before any submission. It survives here because this is a sideloaded app.
  //
  // Spanish is 'configuración', not 'ajustes': the catalog is neutral Latin
  // American, which is what es-419 and es-MX read on iOS. 'ajustes' is es-ES.
  {
    urlString: 'App-Prefs://',
    names: { en: 'settings', 'pt-BR': 'ajustes', es: 'configuración', ja: '設定' },
  },
];

/** Fresh seeds with newly minted ids, mirroring Swift's `LauncherApp(name:urlString:)`. */
export function makeBundledDefaults(language: AppLanguage): LauncherApp[] {
  return SEEDS.map((seed) => ({
    id: Crypto.randomUUID(),
    name: seed.names[language],
    urlString: seed.urlString,
  }));
}

/**
 * The default name for a target in one language, or null if the target is not
 * one of the seeds. Keyed by `urlString` because that is the only field of a
 * seeded row the user cannot change from the UI: names are editable and ids are
 * minted fresh on every launch that has to seed.
 */
export function defaultNameFor(urlString: string, language: AppLanguage): string | null {
  return SEEDS.find((seed) => seed.urlString === urlString)?.names[language] ?? null;
}

/**
 * The app list to store when the language changes.
 *
 * A row is renamed only when it still carries the OUTGOING language's default
 * name for its own target, which is the same test `switchLanguageItems` applies
 * to phrases and it is there for the same reason: everything else is the user's
 * writing and renaming it would discard an edit with no undo. So a row renamed
 * to "zap" stays "zap" in every language, and a row left as "whatsapp" follows.
 *
 * The name is resolved here and stored as plain text, rather than storing a key
 * and resolving it at render time. The widget is a SEPARATE PROCESS reading a
 * shared container, and a key would have to be resolved there too, against a
 * copy of this table compiled into the other target, on a path that runs before
 * any of this code. Text on the wire keeps the widget unchanged.
 */
export function switchLanguageApps(
  from: AppLanguage,
  to: AppLanguage,
  apps: readonly LauncherApp[]
): LauncherApp[] {
  return apps.map((app) => {
    const outgoing = defaultNameFor(app.urlString, from);
    if (outgoing === null || app.name !== outgoing) return app;
    const incoming = defaultNameFor(app.urlString, to);
    // Same object when the name does not actually change, which is most of the
    // table: whatsapp and waze are wordmarks and read the same in all four.
    if (incoming === null || incoming === app.name) return app;
    return { ...app, name: incoming };
  });
}
