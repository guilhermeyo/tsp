/**
 * Typed facade over the local Swift module in `ios/LauncherNativeModule.swift`.
 *
 * Why this exists at all, given that `@bacons/apple-targets` already ships an
 * `ExtensionStorage` module that almost does the same job:
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
 * All four functions are declared with Expo's `Function` (not `AsyncFunction`),
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
}

export const LauncherNative = requireNativeModule<LauncherNativeModule>('LauncherNative');

export default LauncherNative;
