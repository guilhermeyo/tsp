/**
 * Built-in catalog of common apps and their launch URLs.
 *
 * This is the one Swift file that died and was reborn in TypeScript: only the
 * picker UI ever read `Shared/AppCatalog.swift`, and the picker now lives in
 * React Native. Nothing in `targets/widget/` needs it, so there is no twin to
 * keep in sync.
 *
 * Schemes were verified during research; a few Apple-system entries use
 * private or undocumented schemes that work in practice but carry App Store
 * review risk.
 */

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

export const CATALOG: readonly CatalogEntry[] = [
  // Messaging
  entry('WhatsApp', 'whatsapp://', 'Messaging'),
  entry('Telegram', 'tg://', 'Messaging'),
  entry('Messenger', 'fb-messenger://', 'Messaging'),
  entry('Messages', 'sms://', 'Messaging'),

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
