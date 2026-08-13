/**
 * Built-in catalog of common apps and their launch URLs.
 *
 * This is the one Swift file that died and was reborn in TypeScript: only the
 * picker UI ever read `Shared/AppCatalog.swift`, and the picker now lives in
 * React Native. Nothing in `ios/SimplePhoneWidget/` needs it, so there is no twin to
 * keep in sync.
 *
 * Schemes were verified during research; a few Apple-system entries use
 * private or undocumented schemes that work in practice but carry App Store
 * review risk.
 *
 * The catalog is DATA, so its localization lives here rather than in `src/i18n`:
 * the decision about which of these strings may be translated at all belongs
 * next to the strings themselves. See `CATALOG_CATEGORY_LABELS` at the bottom.
 */

import type { AppLanguage } from './types';

export interface CatalogEntry {
  /** The url string doubles as the identity, exactly as in Swift (`var id: String { urlString }`). */
  readonly id: string;
  readonly name: string;
  readonly urlString: string;
  readonly category: string;
  /** True when the scheme was confirmed against a credible source. */
  readonly verified: boolean;
  /** Explains an unverified or risky scheme. Absent for the ordinary case. */
  readonly note?: string;
}

/** Mirrors Swift's `CatalogEntry.init` and its `verified: true, note: nil` defaults. */
function entry(
  name: string,
  urlString: string,
  category: string,
  options?: { verified?: boolean; note?: string }
): CatalogEntry {
  return {
    id: urlString,
    name,
    urlString,
    category,
    verified: options?.verified ?? true,
    ...(options?.note === undefined ? {} : { note: options.note }),
  };
}

// Every `note` below stays ENGLISH on purpose. This is not an oversight and it
// is not about volume — 167 words is an afternoon. It is about VERIFICATION:
//
//   - The Shortcuts note tells the user to build a shortcut whose only action
//     is "Open App". That is the literal name of an action inside Apple's
//     Shortcuts app, and Apple localizes it there. A guessed translation sends
//     the user hunting for an action that does not exist under that name, which
//     is strictly worse than English they can match against what they see.
//   - The Messages note names four URL schemes (sms://, messages://, imessage://,
//     ichat://) that have to survive verbatim.
//   - The Shortcut template note contains "%20", which reflows into something
//     that no longer works if a translator treats it as prose.
//
// Every one of these needs a device in each language to confirm, and they sit
// as secondary text under 8 of 30 rows, read by someone already hand-editing
// URL schemes. Translate them when there is a device to check them on, not
// before.
export const CATALOG: readonly CatalogEntry[] = [
  // Shortcuts — the escape hatch for everything a URL scheme cannot express.
  //
  // A custom scheme names a PROTOCOL, not an app. When two apps register the
  // same one (WhatsApp and WhatsApp Business both claim whatsapp://) iOS picks
  // a winner and no public API lets the caller choose. Apple's own apps have
  // the mirror problem: sms:// names "compose a message", not "open Messages".
  //
  // The Shortcuts app's "Open App" action targets an app by IDENTITY, from a
  // picker, so it has neither problem. Running that shortcut by name is the
  // only reliable way to open one specific installed app. It costs a visible
  // hop through Shortcuts and one shortcut per app, which is exactly the
  // trade the dedicated dumb-phone launchers on the App Store make.
  entry('Shortcut (template)', 'shortcuts://run-shortcut?name=REPLACE%20ME', 'Shortcuts', {
    verified: false,
    note:
      'Create a shortcut whose only action is "Open App" pointing at the app you want, then ' +
      'put its name here, percent-encoded (a space is %20). Use this when a scheme opens the ' +
      'wrong app, such as WhatsApp Business instead of WhatsApp.',
  }),

  // Messaging
  entry('WhatsApp', 'whatsapp://', 'Messaging', {
    note:
      'Claimed by BOTH WhatsApp and WhatsApp Business. With both installed iOS chooses, and it ' +
      'often chooses Business. Use a Shortcut to target one of them specifically.',
  }),
  entry('Telegram', 'tg://', 'Messaging'),
  entry('Messenger', 'fb-messenger://', 'Messaging'),
  entry('Messages', 'ichat://', 'Messaging', {
    verified: false,
    note:
      'iOS 26 made sms://, messages:// and imessage:// all open the COMPOSE sheet instead of ' +
      'the conversation list, which they did correctly through iOS 18. ichat:// is the ' +
      'community-reported scheme that still lands on the list. Undocumented and unverified ' +
      'here — test on device, and fall back to a Shortcut if it stops working.',
  }),
  entry('New message', 'sms://', 'Messaging', {
    note: 'Opens the compose sheet with an empty To: field. This is what sms:// is actually for.',
  }),

  // Social
  entry('Instagram', 'instagram://', 'Social'),
  entry('X (Twitter)', 'twitter://', 'Social'),
  entry('TikTok', 'tiktok://', 'Social'),
  entry('LinkedIn', 'linkedin://', 'Social'),
  entry('Discord', 'discord://', 'Social'),

  // Music & Video
  entry('Spotify', 'spotify://', 'Music & Video'),
  entry('Apple Music', 'music://', 'Music & Video'),
  entry('YouTube', 'youtube://', 'Music & Video'),
  entry('Netflix', 'nflx://', 'Music & Video'),
  entry('YouTube Music', 'youtubemusic://', 'Music & Video', {
    verified: false,
    note: 'Unverified — test on device; fallback https://music.youtube.com',
  }),

  // Maps & Transport
  entry('Apple Maps', 'maps://', 'Maps & Transport'),
  entry('Google Maps', 'comgooglemaps://', 'Maps & Transport'),
  entry('Waze', 'waze://', 'Maps & Transport'),
  entry('Uber', 'uber://', 'Maps & Transport'),

  // Mail & Web
  entry('Gmail', 'googlegmail://', 'Mail & Web'),
  entry('Mail', 'message://', 'Mail & Web'),
  entry('Chrome', 'googlechrome://', 'Mail & Web'),
  entry('Google', 'https://www.google.com', 'Mail & Web'),

  // Productivity
  entry('Slack', 'slack://', 'Productivity'),
  entry('Notion', 'notion://', 'Productivity', {
    verified: false,
    note: 'Unverified — iOS may prefer https://notion.so',
  }),

  // Apple system (private/undocumented schemes — App Store risk)
  entry('Phone', 'tel://', 'System'),
  entry('FaceTime', 'facetime://', 'System'),
  entry('Photos', 'photos-redirect://', 'System', {
    note: 'Undocumented scheme; works but could break in a future iOS',
  }),
  entry('Calendar', 'calshow://', 'System', {
    note: 'Private scheme; works but App Store review risk',
  }),
];

export interface CatalogSection {
  readonly category: string;
  readonly entries: readonly CatalogEntry[];
}

/**
 * Grouped by category, preserving FIRST-SEEN order — not alphabetical.
 * The order is editorial (Messaging first, System last) and comes from the
 * order of `CATALOG` above, exactly like Swift's `AppCatalog.byCategory`.
 */
function groupByCategory(entries: readonly CatalogEntry[]): CatalogSection[] {
  const order: string[] = [];
  const groups = new Map<string, CatalogEntry[]>();
  for (const item of entries) {
    const bucket = groups.get(item.category);
    if (bucket === undefined) {
      order.push(item.category);
      groups.set(item.category, [item]);
    } else {
      bucket.push(item);
    }
  }
  return order.map((category) => ({ category, entries: groups.get(category) ?? [] }));
}

export const byCategory: readonly CatalogSection[] = groupByCategory(CATALOG);

/**
 * The eight category headers, in every language.
 *
 * These are section headers sitting directly above rows the rest of the app has
 * already localized, so leaving them English would be the most visible possible
 * half-translation. English maps each category to itself, which also makes this
 * table the index of the eight valid `category` strings scattered through
 * `CATALOG` above.
 *
 * Non-English headers use sentence case, which is the convention in all three
 * languages; only English capitalizes every word.
 */
export const CATALOG_CATEGORY_LABELS: Record<AppLanguage, Record<string, string>> = {
  'pt-BR': {
    Shortcuts: 'Atalhos',
    Messaging: 'Mensagens',
    Social: 'Social',
    'Music & Video': 'Música e vídeo',
    'Maps & Transport': 'Mapas e transporte',
    'Mail & Web': 'E-mail e web',
    Productivity: 'Produtividade',
    System: 'Sistema',
  },
  en: {
    Shortcuts: 'Shortcuts',
    Messaging: 'Messaging',
    Social: 'Social',
    'Music & Video': 'Music & Video',
    'Maps & Transport': 'Maps & Transport',
    'Mail & Web': 'Mail & Web',
    Productivity: 'Productivity',
    System: 'System',
  },
  es: {
    Shortcuts: 'Atajos',
    Messaging: 'Mensajería',
    Social: 'Social',
    // Unaccented "video" rather than the peninsular "vídeo": one neutral
    // Spanish catalog serves es-419, es-MX and es-ES, and both spellings are
    // correct, so the form the larger group writes wins.
    'Music & Video': 'Música y video',
    'Maps & Transport': 'Mapas y transporte',
    'Mail & Web': 'Correo y web',
    Productivity: 'Productividad',
    System: 'Sistema',
  },
  ja: {
    Shortcuts: 'ショートカット',
    Messaging: 'メッセージ',
    Social: 'ソーシャル',
    'Music & Video': '音楽とビデオ',
    'Maps & Transport': 'マップと交通',
    'Mail & Web': 'メールとWeb',
    // Apple's own App Store category name, not a literal rendering of
    // "productivity", which has no natural noun in Japanese.
    Productivity: '仕事効率化',
    System: 'システム',
  },
};

/**
 * The seven entry names that are NOT proper nouns, keyed by entry id.
 *
 * `id` is the url string (see `CatalogEntry.id`), so these keys survive a
 * rename of the English name — which is the point, since the English name is
 * the thing being replaced.
 *
 * Only these seven move. The other 23 are registered trademarks that appear
 * untranslated on the user's own home screen: translating WhatsApp or Spotify
 * would make the catalog row stop matching the icon it launches, which is the
 * exact defect this table exists to fix in the other direction. A pt-BR home
 * screen says Mensagens, Telefone and Fotos, so a row labelled "Messages" sends
 * the user looking for something they do not have.
 *
 * The six values that name an Apple system app are the names Apple itself uses
 * on the home screen in that language, not translations of the English word.
 * That is why Mail stays "Mail" in Portuguese and Spanish — Apple stopped
 * translating it, so "Correo" would be the wrong answer here even though it is
 * the right translation.
 */
export const CATALOG_NAME_LABELS: Record<AppLanguage, Record<string, string>> = {
  'pt-BR': {
    'shortcuts://run-shortcut?name=REPLACE%20ME': 'Atalho (modelo)',
    'ichat://': 'Mensagens',
    'sms://': 'Nova mensagem',
    'message://': 'Mail',
    'tel://': 'Telefone',
    'photos-redirect://': 'Fotos',
    'calshow://': 'Calendário',
  },
  // Deliberately empty. The English name already lives on the entry and
  // `entryName` falls back to it, so a second copy here could only ever
  // disagree with the first.
  en: {},
  es: {
    'shortcuts://run-shortcut?name=REPLACE%20ME': 'Atajo (plantilla)',
    'ichat://': 'Mensajes',
    'sms://': 'Mensaje nuevo',
    'message://': 'Mail',
    'tel://': 'Teléfono',
    'photos-redirect://': 'Fotos',
    'calshow://': 'Calendario',
  },
  ja: {
    'shortcuts://run-shortcut?name=REPLACE%20ME': 'ショートカット（テンプレート）',
    'ichat://': 'メッセージ',
    'sms://': '新規メッセージ',
    'message://': 'メール',
    'tel://': '電話',
    'photos-redirect://': '写真',
    'calshow://': 'カレンダー',
  },
};

/**
 * Falls back to the raw category string, so a category added to `CATALOG`
 * without a matching row above still renders as a readable header instead of a
 * blank one.
 */
export function categoryLabel(category: string, language: AppLanguage): string {
  const translated: string | undefined = CATALOG_CATEGORY_LABELS[language][category];
  return translated ?? category;
}

/** Falls back to `entry.name`, which is the English name and the only one for 23 of the 30. */
export function entryName(entry: CatalogEntry, language: AppLanguage): string {
  const translated: string | undefined = CATALOG_NAME_LABELS[language][entry.id];
  return translated ?? entry.name;
}
