/**
 * The JS half of the relay contract, twin of `targets/widget/DeepLink.swift`.
 *
 * A widget row NEVER links to the third-party scheme directly, because iOS
 * always delivers a widget tap to the widget's own host app. The row links to
 * `simplephonern://open?u=<target>`, this app parses it, opens the real target
 * and goes straight back.
 *
 * The scheme is `simplephonern`, not `simplephone`: the original Swift app owns
 * `simplephone` and may still be installed on the same device. Two apps
 * claiming one scheme means iOS picks a winner arbitrarily, and widget taps
 * would land in the wrong app. This constant, `app.json`'s `scheme` and
 * `targets/widget/DeepLink.swift` must change together.
 */
export const SCHEME = 'simplephonern';
export const HOST = 'open';
export const QUERY_KEY = 'u';

/**
 * The third-party URL to open, or null if `url` is not one of ours. Mirrors
 * `DeepLink.target(from:)`, which returns nil rather than throwing — the
 * relay's whole response to a malformed link is to do nothing.
 *
 * Parsed with the global `URL` (Expo installs the WHATWG implementation on
 * native) rather than `expo-linking`'s `parse`, which runs an extra
 * `decodeURIComponent` over each query value on top of the one `URLSearchParams`
 * already did. Swift's `URLComponents` decodes exactly once, and a target that
 * legitimately contains a percent-escape — a Google Maps link with an encoded
 * query, say — comes out mangled if it is decoded twice.
 */
export function parseTarget(url: string): string | null {
  let parsed: URL;
  try {
    parsed = new URL(url);
  } catch {
    return null;
  }

  // `protocol` keeps the trailing colon and is already lowercased by the
  // parser. The host is not: for a non-special scheme the WHATWG parser leaves
  // its case alone, while Swift's `URL.host` compares against a normalized
  // form, so normalize here.
  if (parsed.protocol !== `${SCHEME}:`) return null;
  if (parsed.hostname.toLowerCase() !== HOST) return null;

  const target = parsed.searchParams.get(QUERY_KEY);
  // Swift additionally required `URL(string: raw)` to succeed. Skipped on
  // purpose: iOS is the real arbiter of what it can open, and an unopenable URL
  // already ends in the same silent no-op.
  if (target === null || target.length === 0) return null;
  return target;
}
