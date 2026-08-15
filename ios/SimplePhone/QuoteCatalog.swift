import Foundation

/// Everything the cover reads and writes: the phrase catalogue, the shared
/// config the app owns, and the tally of how often each line has been put up.
///
/// Split out of `QuoteScreen`, which had grown to sixteen hundred lines doing
/// five jobs at once and where a change to how a line is chosen sat forty
/// screens away from the window that draws it.
///
/// FOUNDATION ONLY, and that is a rule rather than a coincidence. It is what
/// keeps this half free of the window, the frame deadline and the touch
/// handling, and it is what would let a test compile this file the way
/// `scripts/test-relay-gate` already compiles the gate.
///
/// The App Group is the only channel between this app and its widget, and this
/// is the reader. `launcher_config` belongs to the TypeScript side and is never
/// written here. `quote_stats` is the mirror image: written only here, read by
/// the module that feeds the Phrases screen.
enum QuoteCatalog {
  private static let appGroupId = "group.com.guilherme44.simple-phone"
  private static let configKey = "launcher_config"

  /// A SECOND key in the same suite, and this file is its only writer.
  ///
  /// Counting inside `launcher_config` would make Swift a writer of the payload
  /// holding every app the user added, and a backgrounding can land in the
  /// middle of a JS save: last writer wins on the whole blob, so an increment
  /// could cost the user their list.
  ///
  /// Duplicated in `modules/launcher-native/ios/LauncherNativeModule.swift`,
  /// which reads it for the Phrases screen. Two copies of a string with nothing
  /// enforcing agreement; a drift shows up as counters frozen at zero with no
  /// error anywhere.
  private static let quoteStatsKey = "quote_stats"

  /// True once THIS process has drawn a line of its own.
  private static var rolledThisLaunch = false

  // MARK: - Content

  /// Draws the line for the NEXT cover, counts it, and remembers it.
  ///
  /// The one place a phrase is ever chosen. Counting AT THE DRAW rather than
  /// when the line is retired is what keeps the number honest: a line is put
  /// up exactly once per draw, so one draw is one increment, with no second
  /// write anywhere and nothing to reconcile if the process is killed while
  /// backgrounded.
  ///
  /// The number therefore means "times this line was put up as a cover", which
  /// includes the app-switcher card and a plain icon launch. That is not a
  /// rounding error, it is the same accepted side effect the header of this
  /// file already documents: iOS gives no way to know at snapshot time which
  /// path the next foreground will take.
  static func roll(_ config: Config) -> Quote? {
    rolledThisLaunch = true
    guard config.enabled else { return nil }

    var stats = loadStats()
    guard let next = pick(from: config.items, counts: stats.counts, excluding: stats.current) else {
      return nil
    }
    // NOT COUNTED HERE. Drawing a line is not showing it to anybody: this runs
    // on a backgrounding, and what it paints may be replaced by the return card
    // before a human ever reads it, or may never be foregrounded at all. The
    // tally is incremented by `countAsShown`, on the relay that actually puts
    // the line in front of someone.
    stats.current = next.text
    saveStats(stats, items: config.items)
    return next
  }

  /// Counts a line at the moment it becomes the cover of a real relay.
  ///
  /// Splitting this out of `roll` is what lets the roll stay where it belongs.
  /// The two were the same call, so keeping a phrase for the return card meant
  /// not rolling, and not rolling meant the line froze for anyone who only ever
  /// uses the widget: the pending return that gates the skip is only consumed
  /// by opening the app, which that person never does. The freeze was the old
  /// "phrase that never changed" bug coming back through another door.
  ///
  /// Counting here also retires an accepted inaccuracy the header of this file
  /// used to describe: the app-switcher card and a plain icon launch put the
  /// cover up without anyone launching anything, and used to score for it. Now
  /// they do not.
  static func countAsShown(_ text: String?, config: Config) {
    guard let text, config.enabled else { return }
    var stats = loadStats()
    stats.counts[text, default: 0] += 1
    saveStats(stats, items: config.items)
  }

  /// The cold relay, and the one case where NOT rolling is the right answer.
  ///
  /// The process was killed while backgrounded, so the image iOS is replaying
  /// over this launch was painted by a process that is gone. Restoring the line
  /// that snapshot carries is what keeps the first live frame equal to it;
  /// rolling a new one would swap the text under an image already on screen, on
  /// the path where the swap is most visible. This is a hole in the
  /// snapshot-matching guarantee that predates the counters and that the stored
  /// `current` closes for free.
  ///
  /// `rolledThisLaunch` is what makes it safe. Once this process has drawn a
  /// line of its own, the stored one is merely the line it just took down, and
  /// putting it back up would be the repeat this whole change is about.
  ///
  /// Costs one extra key read on a path that is already booting all of React
  /// Native, and no write at all unless there is nothing stored yet -- which is
  /// once per install.
  static func restoreOrRoll(_ config: Config) -> Quote? {
    guard config.enabled else { return nil }
    // Matched on TEXT, so re-attributing a line does not lose the snapshot it
    // is already carrying; the restored Quote is the CURRENT one, so an author
    // edited since the snapshot was taken shows up on the first live frame.
    if !rolledThisLaunch,
       let current = loadStats().current,
       let restored = config.items.first(where: { $0.text == current }) {
      rolledThisLaunch = true
      return restored
    }
    return roll(config)
  }

  /// Uniform over the least-shown tier, never the line just taken down.
  ///
  /// A bag shuffle whose bag is RECOMPUTED from the counts instead of stored,
  /// so the number the user reads in the Phrases screen IS the algorithm's
  /// entire state. Nothing to invalidate when a phrase is added, deleted or the
  /// language flips: an item with no entry reads as zero and lands in the
  /// bottom tier, which is exactly where a new line belongs.
  ///
  /// Excluding `current` is the only part of this anyone will ever perceive.
  /// A back-to-back repeat was already just 1 in 101 with `randomElement`; this
  /// makes it impossible, which matters because it is the ONE repeat a person
  /// actually notices. The rest is a real but unobservable improvement to the
  /// long tail, and it should be described that way -- the phrase that never
  /// changed was the stuck window, not the draw.
  ///
  /// THE FLOOR is the part that is not obvious. Strict least-shown-first would
  /// take a freshly added line (count 0, alone at the bottom of the ranking)
  /// and show it on every single backgrounding until it caught up with the rest
  /// -- forty in a row on a list that has been in use a month, manufacturing
  /// precisely the repetitiveness this exists to remove. Widening the tier to
  /// at least `max(5, count / 8)` candidates (12 at the bundled 101) keeps a
  /// new line arriving within a handful of relays, takes it out of the running
  /// for two in a row, and still draws from the strict minimum for most of a
  /// cycle, because the tier only widens once the minimum tier runs thin.
  private static func pick(from items: [Quote], counts: [String: Int], excluding current: String?) -> Quote? {
    guard items.count > 1 else { return items.first }

    // The fallback covers a config that somehow holds nothing but duplicates of
    // the current line; the contract is the cover, so this may not return nil
    // for a list that has items in it.
    let pool = items.filter { $0.text != current }
    let candidates = pool.isEmpty ? items : pool

    // Sorting 101 strings, on the backgrounding path, with no frame deadline
    // and nobody watching. The deterministic tie-break keeps the ranking stable
    // between draws; the randomness comes from the pick within the tier.
    let ranked = candidates.sorted { lhs, rhs in
      let left = counts[lhs.text] ?? 0
      let right = counts[rhs.text] ?? 0
      return left == right ? lhs.text < rhs.text : left < right
    }
    guard let first = ranked.first else { return nil }

    let lowest = counts[first.text] ?? 0
    let floor = min(ranked.count, max(5, items.count / 8))
    var tier = ranked.prefix { (counts[$0.text] ?? 0) == lowest }
    if tier.count < floor {
      tier = ranked.prefix(floor)
    }
    return tier.randomElement()
  }

  /// How many times each line has been put up, and which one the last snapshot
  /// carries.
  ///
  /// Keyed by the phrase TEXT, not by index: `removeQuoteAt` splices, so every
  /// count past a deleted row would silently slide onto the wrong line.
  /// `addQuote` already refuses an exact duplicate, so the text is a unique,
  /// stable key with no id scheme and no migration for the 202 bundled lines.
  /// The consequence worth knowing: a future edit-a-phrase UI would zero that
  /// line's history, and the Phrases screen DOES edit: `updateQuote` renames a
  /// line in place, which orphans its count and the `current` restore key. The
  /// orphan is pruned on the next write and the restore falls through to a
  /// fresh roll, so the cost is one forgotten counter, not a broken screen.
  struct Stats {
    var counts: [String: Int] = [:]
    var current: String?
  }

  /// Resilient in the same way `loadConfig` is, and for the same reason: a
  /// corrupt payload here must degrade to "no history", never to a throw on the
  /// path that puts the cover up.
  static func loadStats() -> Stats {
    let defaults = UserDefaults(suiteName: appGroupId) ?? .standard
    let data = defaults.data(forKey: quoteStatsKey)
      ?? defaults.string(forKey: quoteStatsKey)?.data(using: .utf8)
    let root = data.flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any]

    // Element-wise rather than a blanket `as? [String: Int]`, so one junk value
    // costs that entry and not the whole table.
    var counts: [String: Int] = [:]
    for (key, value) in (root?["counts"] as? [String: Any]) ?? [:] {
      guard let number = value as? NSNumber else { continue }
      counts[key] = number.intValue
    }
    return Stats(counts: counts, current: root?["current"] as? String)
  }

  private static func saveStats(_ stats: Stats, items: [Quote]) {
    var counts = stats.counts
    // Keys for lines no longer in rotation are KEPT on purpose. It is what
    // makes a language round trip non-destructive (the four catalogs are
    // disjoint, so pruning would zero the others permanently), and a count is
    // only ever looked up for an item that is in the list right now, so a stale
    // key cannot reach the draw. The bound exists only so that pasting in a very
    // large list cannot grow a blob that is rewritten on every backgrounding.
    //
    // It has to clear the sum of every bundled catalog for the guarantee above
    // to hold: four languages at 101 lines each is 404 keys that all have to fit
    // alongside whatever the user wrote themselves.
    if counts.count > 1200 {
      let live = Set(items.map(\.text))
      counts = counts.filter { live.contains($0.key) }
    }

    var payload: [String: Any] = ["counts": counts]
    if let current = stats.current {
      payload["current"] = current
    }
    guard let data = try? JSONSerialization.data(withJSONObject: payload),
          let json = String(data: data, encoding: .utf8)
    else { return }

    // Written as a String so the module reads it back with a plain
    // `string(forKey:)`, matching how the app writes `launcher_config`.
    // `loadStats` accepts both forms anyway.
    (UserDefaults(suiteName: appGroupId) ?? .standard).set(json, forKey: quoteStatsKey)
  }

  /// One line and, optionally, who said it.
  ///
  /// Decoded from BOTH wire shapes: a bare string when there is no author, an
  /// object when there is. `text` alone is the identity everywhere else --
  /// stats keys, the "not the one just shown" exclusion, the restore lookup --
  /// so attribution can be edited without orphaning a counter.
  struct Quote: Equatable {
    let text: String
    let author: String?
  }

  struct Config {
    let enabled: Bool
    let items: [Quote]
    let isDark: Bool
    let font: String
    /// The interface language the user settled on, as a stored BCP-47 tag, or
    /// nil when nothing has ever been written. Carried here so the relay's
    /// failure alert can be worded in it -- it is the only string this process
    /// writes that the user reads.
    let language: String?
    /// Resolved by the app from its named durations, so this side never carries
    /// the label table. Clamped on read: a corrupt payload must not be able to
    /// freeze the launcher on a phrase.
    let holdSeconds: TimeInterval
  }

  /// The stored language, for the one caller outside this file: AppDelegate's
  /// failure alert. Re-reads the config rather than caching it, which is free on
  /// a path that has already given up on opening anything.
  static func configuredLanguage() -> String? {
    loadConfig().language
  }

  /// Hand-rolled rather than Codable structs: this needs five fields out of a
  /// payload that belongs to the JS side, and a synthesized decoder would fail
  /// the whole parse over any key it did not expect.
  ///
  /// NEVER FAILS, by design. Every field defaults independently, exactly as
  /// `decodeTheme` does on the TypeScript side and for the same reason. The old
  /// version returned nil for the whole config if any one of five things was
  /// missing, and the caller turned that nil into "open with nothing on
  /// screen".
  static func loadConfig() -> Config {
    // `?? .standard` matches ConfigStore.swift and LauncherNativeModule.swift.
    // On a build whose App Group entitlement did not sign, the app writes to
    // .standard, and reading the same place is better than reading nothing.
    let defaults = UserDefaults(suiteName: appGroupId) ?? .standard
    let data = defaults.data(forKey: configKey)
      ?? defaults.string(forKey: configKey)?.data(using: .utf8)
    let root = data.flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any]
    let quotes = root?["quotes"] as? [String: Any]
    let theme = root?["theme"] as? [String: Any]

    // Top-level `language` is authoritative. `quotes.language` is read only as
    // a fallback, for a config written by a build that still mirrored it there.
    let language = (root?["language"] as? String) ?? (quotes?["language"] as? String)
    let stored = ((quotes?["items"] as? [Any]) ?? []).compactMap(Self.decodeQuote)

    return Config(
      enabled: quotes?["enabled"] as? Bool ?? true,
      // An empty or absent list is "never seeded", not "the user deleted every
      // line". Deleting the last phrase is what the `enabled` switch is for.
      items: stored.isEmpty ? bundledItems(language: language) : stored,
      isDark: theme?["isDark"] as? Bool ?? true,
      font: theme?["font"] as? String ?? "monospaced",
      language: language,
      // Absent means 0, not some invented default: `instant` is the app's own
      // first-run duration, and inventing a wait here would be exactly the
      // artificial delay this feature is not allowed to add.
      holdSeconds: min(max((quotes?["durationMs"] as? Double ?? 0) / 1000, 0), 8))
  }

  /// The full catalog, read from the same `quotes.json` the TypeScript side
  /// imports. Used only when the shared config has nothing usable -- a fresh
  /// install, a config written before quotes existed, an unsigned App Group.
  /// Without it, the cover on those paths would be a blank coloured screen.
  private static let bundledCatalog: [String: Any] = {
    guard let url = Bundle.main.url(forResource: "quotes", withExtension: "json"),
          let data = try? Data(contentsOf: url),
          let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else { return [:] }
    return root
  }()

  /// A bare string is an unattributed line; an object carries `text` and an
  /// optional `author`. An author that trims to nothing becomes nil, so the
  /// renderer never has to distinguish absent from empty.
  private static func decodeQuote(_ raw: Any) -> Quote? {
    if let text = raw as? String {
      let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
      return trimmed.isEmpty ? nil : Quote(text: trimmed, author: nil)
    }
    guard let object = raw as? [String: Any],
          let text = object["text"] as? String
    else { return nil }
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.isEmpty { return nil }
    let author = (object["author"] as? String)?
      .trimmingCharacters(in: .whitespacesAndNewlines)
    return Quote(text: trimmed, author: (author?.isEmpty ?? true) ? nil : author)
  }

  private static func bundledItems(language: String?) -> [Quote] {
    if let language, let items = catalogPhrases(matching: language) {
      return items
    }

    // THE SYSTEM STEP, and it is not a second resolver competing with the app's.
    // It is reachable ONLY while the shared container holds no phrase list at
    // all -- a fresh install whose first ever action was a widget tap, before
    // JavaScript has run once. The moment the app writes a config, the stored
    // `language` above wins unconditionally and this line is dead. Without it a
    // brand-new install would show its very first cover in whatever
    // `defaultLanguage` happens to say, regardless of the phone.
    if let system = Locale.preferredLanguages.first, let items = catalogPhrases(matching: system) {
      return items
    }

    // The default language lives in the catalog rather than being re-decided
    // here, so Swift cannot drift from the TypeScript side.
    let fallback = bundledCatalog["defaultLanguage"] as? String ?? "en"
    return ((bundledCatalog[fallback] as? [Any]) ?? []).compactMap(decodeQuote)
  }

  /// A BCP-47 tag to one of the catalog's phrase arrays: exact key first, then
  /// the two-letter primary subtag, mirroring `matchLanguage` on the TypeScript
  /// side. Underscores are normalised because `Locale` spells regions with one
  /// ("pt_BR") while the catalog keys use hyphens.
  ///
  /// The `as? [Any]` cast is also the guard against the catalog's non-phrase
  /// keys: `relay` is a dictionary and `defaultLanguage` is a string, so neither
  /// can ever be returned as a phrase list even when a tag prefix-matches their
  /// name. Keys are sorted so a tie between two candidates is at least stable.
  private static func catalogPhrases(matching tag: String) -> [Quote]? {
    let normalized = tag.replacingOccurrences(of: "_", with: "-").lowercased()
    guard !normalized.isEmpty else { return nil }
    let prefix = String(normalized.prefix(2))
    let keys = bundledCatalog.keys.sorted()
    let key = keys.first { $0.lowercased() == normalized }
      ?? keys.first { $0.lowercased().hasPrefix(prefix) }
    guard let key, let raw = bundledCatalog[key] as? [Any] else { return nil }
    let items = raw.compactMap(decodeQuote)
    return items.isEmpty ? nil : items
  }

  /// The relay's failure alert, in the user's language, from the same
  /// `quotes.json` the app imports. `AppDelegate` is the only caller.
  ///
  /// This is technically a SECOND matcher, and it is safe only because it
  /// matches the STORED tag and never the system locale: `config.language` is
  /// always one of the four exact keys in the relay table, so it cannot disagree
  /// with the JavaScript resolver about which language the user is in. If a
  /// future build ever stores a tag the table lacks, the worst case is English.
  ///
  /// The English table is the base and the matched one is merged over it, so a
  /// half-finished translation renders its finished keys and English for the
  /// rest rather than nothing at all.
  static func relayStrings(language: String?) -> [String: String] {
    let table = bundledCatalog["relay"] as? [String: Any] ?? [:]
    let english = table["en"] as? [String: String] ?? [:]
    guard let language else { return english }

    let normalized = language.replacingOccurrences(of: "_", with: "-").lowercased()
    guard !normalized.isEmpty else { return english }
    let prefix = String(normalized.prefix(2))
    let keys = table.keys.sorted()
    let key = keys.first { $0.lowercased() == normalized }
      ?? keys.first { $0.lowercased().hasPrefix(prefix) }
    guard let key, let localized = table[key] as? [String: String] else { return english }
    return english.merging(localized) { _, new in new }
  }
}
