import { HOST, QUERY_KEY, SCHEME, parseTarget } from '../deepLink';

/**
 * The JS half of a contract whose other half is Swift, in another target, in
 * another process. Nothing links the two at build time, so these tests are the
 * only place the agreement is written down executably.
 */

const link = (target: string): string =>
  `${SCHEME}://${HOST}?${QUERY_KEY}=${encodeURIComponent(target)}`;

describe('parseTarget', () => {
  it('reads back what a widget row writes', () => {
    expect(parseTarget(link('whatsapp-consumer://'))).toBe('whatsapp-consumer://');
  });

  /**
   * The reason this uses the WHATWG `URL` and not `expo-linking`'s `parse`,
   * which decodes each query value a second time on top of the one
   * `URLSearchParams` already did. Swift's `URLComponents` decodes exactly once,
   * so a target carrying its own percent-escapes comes back mangled and the two
   * halves disagree.
   */
  it('decodes exactly once, so an escaped target survives', () => {
    const target = 'https://maps.apple.com/?q=Joinville%20SC&z=15';
    expect(parseTarget(link(target))).toBe(target);
  });

  it('keeps a target that carries a plus and an ampersand', () => {
    const target = 'https://example.com/?a=1+2&b=x%26y';
    expect(parseTarget(link(target))).toBe(target);
  });

  it.each([
    ['the old app’s scheme', 'simplephone://open?u=x'],
    ['some other app', 'whatsapp://open?u=x'],
    ['the right scheme, wrong host', `${SCHEME}://close?u=x`],
    ['no query at all', `${SCHEME}://${HOST}`],
    ['the wrong query key', `${SCHEME}://${HOST}?url=x`],
    ['an empty target', `${SCHEME}://${HOST}?${QUERY_KEY}=`],
    ['not a url', 'nonsense'],
    ['empty', ''],
  ])('returns null for %s', (_label, url) => {
    expect(parseTarget(url)).toBeNull();
  });

  /**
   * `simplephone` is the ORIGINAL Swift app, which may still be installed on
   * the same device. Two apps claiming one scheme means iOS picks a winner
   * arbitrarily, which is why this one is `simplephonern` and why the rejection
   * above is not merely a formality.
   */
  it('is not the scheme the original app owns', () => {
    expect(SCHEME).toBe('simplephonern');
  });

  it('accepts the scheme in any case, the way the parser normalizes it', () => {
    expect(parseTarget(`SimplePhoneRN://OPEN?${QUERY_KEY}=ichat%3A%2F%2F`)).toBe('ichat://');
  });
});
