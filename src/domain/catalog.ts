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
