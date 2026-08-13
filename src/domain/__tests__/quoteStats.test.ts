import { countNeverShown, parseQuoteCounts } from '../quoteStats';

import type { Quote } from '../types';

/**
 * `quote_stats` is written by the Swift side and only read here, so every
 * malformed case below is a real possibility rather than a hypothetical: a
 * version skew between the app on the phone and the widget beside it produces
 * exactly these shapes. A settings screen must never crash because a counter
 * blob is from last week.
 */

describe('parseQuoteCounts', () => {
  it('reads the shape the native side writes', () => {
    expect(parseQuoteCounts('{"counts":{"a":3,"b":1}}')).toEqual({ a: 3, b: 1 });
  });

  it.each([
    ['empty', ''],
    ['not json', '{'],
    ['null', 'null'],
    ['an array', '[]'],
    ['a bare number', '7'],
    ['no counts key', '{"other":1}'],
    ['counts as an array', '{"counts":[1,2]}'],
    ['counts as null', '{"counts":null}'],
  ])('reads %s as no counts at all', (_label, raw) => {
    expect(parseQuoteCounts(raw)).toEqual({});
  });

  /**
   * A count is a number of times something was shown. Zero, negative, NaN and
   * a string are all "this key means nothing", and dropping them is what keeps
   * `countNeverShown` honest: a key present with a junk value would otherwise
   * read as shown.
   */
  it.each([
    ['zero', 0],
    ['negative', -1],
    ['a string', '3'],
    ['null', null],
    ['a bool', true],
  ])('drops a count of %s', (_label, value) => {
    expect(parseQuoteCounts(JSON.stringify({ counts: { a: value, b: 2 } }))).toEqual({ b: 2 });
  });

  it('drops the infinities and NaN, which JSON writes as null', () => {
    expect(parseQuoteCounts('{"counts":{"a":1e999,"b":2}}')).toEqual({ b: 2 });
  });

  it('floors a fraction rather than rendering 2.5 times', () => {
    expect(parseQuoteCounts('{"counts":{"a":2.7}}')).toEqual({ a: 2 });
  });
});

describe('countNeverShown', () => {
  const items: Quote[] = [{ text: 'a' }, { text: 'b', author: 'x' }, { text: 'c' }];

  it('counts the lines with no entry', () => {
    expect(countNeverShown(items, { a: 3 })).toBe(2);
  });

  it('is the whole list when nothing has been shown', () => {
    expect(countNeverShown(items, {})).toBe(3);
  });

  it('walks to zero as the rotation completes a cycle', () => {
    expect(countNeverShown(items, { a: 1, b: 1, c: 1 })).toBe(0);
  });

  /**
   * Keyed by TEXT, never by index: indices shift on delete, and every count
   * after a removed row would silently land on the wrong phrase. It is also why
   * the author is not part of the key, so editing an attribution does not reset
   * a counter.
   */
  it('ignores the author when matching', () => {
    expect(countNeverShown([{ text: 'b', author: 'someone else' }], { b: 4 })).toBe(0);
  });

  it('ignores counts for lines that are no longer in the list', () => {
    expect(countNeverShown([{ text: 'a' }], { a: 1, deleted: 99 })).toBe(0);
  });

  it('is zero for an empty list', () => {
    expect(countNeverShown([], { a: 1 })).toBe(0);
  });

  /**
   * The keys are phrases the USER typed, so nothing stops one being called
   * 'toString'. Read off a plain object it finds the inherited function, which
   * is not undefined, and the line reads as already shown forever.
   */
  it.each(['toString', 'constructor', 'valueOf', '__proto__'])(
    'does not let the inherited %s read as a count',
    (text) => {
      expect(countNeverShown([{ text }], parseQuoteCounts('{"counts":{"other":1}}'))).toBe(1);
    }
  );

  it('still counts a line genuinely called toString once it is shown', () => {
    expect(countNeverShown([{ text: 'toString' }], parseQuoteCounts('{"counts":{"toString":3}}'))).toBe(0);
  });
});
