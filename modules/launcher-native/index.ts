/**
 * Typed facade over the local Swift module in `ios/LauncherNativeModule.swift`.
 *
 * Why this exists at all. While this project was still on CNG it could have used
 * `ExtensionStorage` from `@bacons/apple-targets`, which almost does the same
 * job. (That package is no longer a dependency — see "This is a bare project"
 * in the README — but the reasoning is what keeps this module hand-written, so
 * it is worth stating.) Three reasons:
 *
 *  1. `ExtensionStorage.setObject` round-trips the value through object
 *     bridging / JSONSerialization, which can hand Swift the number 1 where JS
 *     had `true`. Swift's `decodeIfPresent(Bool.self, ...)` THROWS
 *     `typeMismatch` on a number — it returns nil only for absent or null keys
 *     — so the throw escapes `Theme.init(from:)`, gets swallowed by `try?` in
 *     `ConfigStore.load()`, and the ENTIRE config silently resets to defaults.
 *     Every app the user added disappears with no error anywhere. Passing a
 *     string across the boundary makes that class of bug impossible: JS owns
 *     the exact bytes, JSONDecoder reads exactly those bytes.
 *  2. It cannot read the legacy value. The original Swift app wrote
 *     `launcher_config` as `Data`; our reader tries `data(forKey:)` first and
 *     `string(forKey:)` second, so an existing install upgrades in place.
 *  3. It has no font resolver. `UIFontDescriptor.withDesign` is the only
 *     public way to turn SwiftUI's `Font.Design` into a family name React
 *     Native can render, and nothing off the shelf exposes it.
 *
 * Every function is declared with Expo's `Function` (not `AsyncFunction`),
 * so they are installed as synchronous JSI functions and return values
 * directly. The store can therefore load the config during render, matching
 * the old synchronous `LauncherStore.init` -> `ConfigStore.load()`.
 */
import { requireNativeModule } from 'expo';

export interface LauncherNativeModule {
  /** App Group whose UserDefaults suite the app and the widget share. */
  readonly appGroupId: string;
  /** UserDefaults key holding the config JSON. */
  readonly configKey: string;

  /** Raw config JSON, or null when nothing has ever been written. */
  readConfigJSON(): string | null;

  /**
   * Persists the config JSON verbatim.
   *
   * Always pass `JSON.stringify(config)`. Never introduce an overload that
   * takes an object: see reason 1 in the header.
   */
  writeConfigJSON(json: string): void;

  /** Invalidates the widget's timeline so WidgetKit re-renders it. */
  reloadWidget(): void;

  /**
   * Concrete font family for a SwiftUI font design name
   * (`monospaced` | `rounded` | `serif`), or null for `system` and for
   * anything unrecognised, meaning "use React Native's default".
   */
  resolvedFontFamily(design: string): string | null;

  /**
   * The phone's top language preference as a BCP-47 tag ('pt-BR', 'en-US',
   * 'es-419'), or 'en' when the list is somehow empty.
   *
   * Read ONCE, on first run, to seed `config.language`. The stored value is a
   * concrete tag from then on, so changing the phone's language later does not
   * silently rewrite the phrase catalog of someone who chose the other one.
   */
  preferredLanguage(): string;

  /**
   * Whether the phone's region measures in metric, which for this app means
   * Celsius. False only for the United States.
   *
   * Also read once, to seed `weather.unit`.
   */
  prefersMetric(): boolean;
}

export const LauncherNative = requireNativeModule<LauncherNativeModule>('LauncherNative');

export default LauncherNative;
