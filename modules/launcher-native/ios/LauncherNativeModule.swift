import ExpoModulesCore
import WidgetKit
import UIKit

// The two strings that make the whole thing work. They are duplicated in
// ios/SimplePhoneWidget/ConfigStore.swift (which cannot import this module: a widget
// extension is a separate binary and does not link the app's Expo modules) and
// in the TypeScript store. If any of the three copies drifts by a single byte,
// the app and the widget quietly stop seeing the same data.
private let appGroupId = "group.com.guilherme44.simple-phone"
private let configKey = "launcher_config"

// The phrase counters. Written ONLY by ios/SimplePhone/QuoteScreen.swift, where
// the other copy of this string lives, and only ever read here. Same duplication
// hazard as the two above: nothing enforces agreement, and a drift shows up as
// counters frozen at zero with no error anywhere.
private let quoteStatsKey = "quote_stats"

/// The one UserDefaults suite the app and the widget share.
///
/// An App Group is a container the system hands to every process signed with
/// the same `com.apple.security.application-groups` entitlement. Without it,
/// the app and the widget each get their own sandboxed `UserDefaults.standard`
/// and cannot see each other's writes at all: two processes, two disks.
///
/// `UserDefaults(suiteName:)` returns nil when the suite name is unusable,
/// which in practice means the entitlement was not granted to this build.
/// The `?? .standard` fallback is deliberate and it is NOT a silent bug fix:
/// the app keeps working on its own defaults, but the widget is a different
/// process reading a different sandbox, so it will render BundledDefaults
/// forever and never reflect anything the user does in the app. That is a
/// signing-tier symptom (free personal team, missing entitlement, stale
/// provisioning profile), and no runtime check here can tell you which — the
/// suite is nil either way. If the widget looks frozen on the default five
/// rows, suspect signing before suspecting this file.
private func sharedDefaults() -> UserDefaults {
  UserDefaults(suiteName: appGroupId) ?? .standard
}

public class LauncherNativeModule: Module {
  // `definition()` is a DSL, not imperative code: it runs once at module
  // registration and describes the JS-visible surface. Everything declared
  // with `Function` (as opposed to `AsyncFunction`) is installed as a real
  // synchronous JSI function, so JS calls it on the same thread and gets the
  // return value immediately — no promise, no bridge hop. That is what lets
  // the TypeScript store load the config during the first render, exactly
  // like the old Swift `LauncherStore.init` called `ConfigStore.load()`
  // synchronously, with no splash screen and no loading state.
  public func definition() -> ModuleDefinition {
    // The name JS passes to requireNativeModule('LauncherNative'). It must
    // match the class listed in expo-module.config.json.
    Name("LauncherNative")

    // Constants are read once at module install time and exposed as plain
    // properties on the JS object. Handy for asserting in JS that both sides
    // agree on the contract without hardcoding the strings twice.
    Constants([
      "appGroupId": appGroupId,
      "configKey": configKey,
    ])

    /// Returns the raw config JSON, or nil when nothing has ever been written.
    ///
    /// Two reads, and the order matters. The ORIGINAL Swift app stored the
    /// config as `Data` (the output of `JSONEncoder`), so on a phone that
    /// already has that app installed the value under `launcher_config` is a
    /// Data object, and `string(forKey:)` returns nil for it. This app writes
    /// a UTF-8 String instead, because JS owning the exact bytes is the whole
    /// point (see writeConfigJSON below). Reading Data first and String second
    /// means an existing install upgrades in place with no migration step, and
    /// the first save transparently converts the value to the String form.
    Function("readConfigJSON") { () -> String? in
      let defaults = sharedDefaults()

      if let data = defaults.data(forKey: configKey) {
        return String(data: data, encoding: .utf8)
      }

      return defaults.string(forKey: configKey)
    }

    /// Persists the config JSON verbatim.
    ///
    /// The parameter is a String and it will never be anything else. This is
    /// the single most important line in the module. If this took a Dictionary
    /// and let Expo bridge a JS object into it, a JS `true` can arrive as the
    /// number 1 — and Swift's `decodeIfPresent(Bool.self, ...)` THROWS
    /// `typeMismatch` on a number (it returns nil only for absent or null
    /// keys). That throw escapes Theme's otherwise resilient init, gets
    /// swallowed by `try?` in ConfigStore.load(), and the entire config —
    /// every app the user added — silently resets to `.default`. Keeping the
    /// boundary a string means JSON.stringify in JS decides the bytes and
    /// JSONDecoder in the widget reads exactly those bytes.
    Function("writeConfigJSON") { (json: String) -> Void in
      sharedDefaults().set(json, forKey: configKey)
      // No `synchronize()`: it has been a no-op-ish legacy call since iOS 12.
      // UserDefaults flushes on its own, and the widget reload below is
      // scheduled by the system after this turn of the run loop anyway.
    }

    /// How many times each phrase has been put up as a relay cover, plus the
    /// one the last snapshot carries.
    ///
    /// READ ONLY, and it stays that way. `QuoteScreen` in the app target is the
    /// sole writer of this key, the exact mirror of `launcher_config`, whose
    /// sole writer is JS. One writer per key is what makes both safe with no
    /// locking anywhere: `QuoteScreen` touches it only from
    /// `didEnterBackground` and from the URL callout, both main-thread, so even
    /// a burst of rapid relays serialises into sequential read-modify-writes on
    /// the run loop. Adding a write here — a "reset counts" button, say — would
    /// introduce a second writer on the JS thread and would have to hop to main.
    ///
    /// Returns `{"counts":{"<phrase>":<int>},"current":"..."}`, or nil before
    /// the first backgrounding of a fresh install. A String rather than a
    /// bridged dictionary for the same reason `writeConfigJSON` takes one: this
    /// boundary is stringly typed everywhere or it is nowhere.
    Function("readQuoteStatsJSON") { () -> String? in
      let defaults = sharedDefaults()

      if let data = defaults.data(forKey: quoteStatsKey) {
        return String(data: data, encoding: .utf8)
      }

      return defaults.string(forKey: quoteStatsKey)
    }

    /// Tells WidgetKit that the timeline is stale.
    ///
    /// A widget is not a live view. It is a separate extension process that
    /// the system wakes on ITS schedule, asks for a timeline of pre-rendered
    /// entries, then kills. The rendered snapshot keeps being displayed while
    /// the process is dead. `reloadAllTimelines()` invalidates those snapshots
    /// and asks the system to re-run the provider — soon, not immediately, and
    /// subject to the system's budget. So a config change shows up on the home
    /// screen within a moment, not on the same frame; that lag is WidgetKit,
    /// not this call failing.
    Function("reloadWidget") { () -> Void in
      WidgetCenter.shared.reloadAllTimelines()
    }

    /// Maps a SwiftUI `Font.Design` name to a concrete font family React Native
    /// can put in a `fontFamily` style.
    ///
    /// The widget renders with `.system(size:design:)`, which is a *request*
    /// resolved by the system at draw time — there is no font name involved,
    /// and RN has no equivalent concept. `UIFontDescriptor.withDesign` is the
    /// public API that performs the same resolution eagerly and hands back a
    /// real font, so the in-app preview can use the same faces (SF Mono,
    /// SF Rounded, New York) the widget will actually draw.
    ///
    /// Returns nil for "system" and for anything unrecognised, meaning "let
    /// React Native use its own default" — which IS the system font.
    Function("resolvedFontFamily") { (design: String) -> String? in
      let systemDesign: UIFontDescriptor.SystemDesign
      switch design {
      case "rounded": systemDesign = .rounded
      case "serif": systemDesign = .serif
      case "monospaced": systemDesign = .monospaced
      default: return nil
      }

      // The size is irrelevant — a family name does not depend on it — but
      // UIFont has no size-less constructor, so pick the body default.
      let base = UIFont.systemFont(ofSize: 17)
      guard let descriptor = base.fontDescriptor.withDesign(systemDesign) else {
        return nil
      }

      // familyName, not fontName: RN's iOS text layer looks up families and
      // then picks a weight within them. Note these are the system's hidden
      // families (names starting with a dot), which RN can render but which
      // are not guaranteed API — hence the fallback table on the JS side.
      return UIFont(descriptor: descriptor, size: 17).familyName
    }

    /// The phone's top language preference, as a BCP-47 tag.
    ///
    /// `Locale.preferredLanguages` is the ordered list from Settings, not the
    /// app's resolved locale, which is what we want: the app ships no
    /// localizations, so `Locale.current` would report whatever the bundle
    /// happens to fall back to, while this reports what the person actually
    /// chose. The caller only looks at the language subtag, so the region
    /// suffix ('pt-BR' vs 'pt-PT') is passed through untouched.
    ///
    /// Read once, to seed `config.language`. After that the config owns the
    /// value, so changing the phone's language does not rewrite a choice the
    /// user made deliberately.
    Function("preferredLanguage") { () -> String in
      Locale.preferredLanguages.first ?? "en"
    }

    /// Whether this region measures in metric, which here means Celsius.
    ///
    /// `measurementSystem` (iOS 16+, and the deployment target is 16.4) has
    /// three cases: `.metric`, `.us` and `.uk`. Comparing against `.us` rather
    /// than for `.metric` is deliberate — the UK is its own system but reports
    /// temperature in Celsius, so it belongs on the metric side of this
    /// particular question.
    Function("prefersMetric") { () -> Bool in
      Locale.current.measurementSystem != .us
    }
  }
}
