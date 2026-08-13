import { StyleSheet, Text, View } from 'react-native';

import type { CatalogEntry } from '@/domain/catalog';
import { useStrings } from '@/i18n/useStrings';

/**
 * Twin of `CatalogPickerView`'s Button label: a leading-aligned VStack(spacing: 2)
 * holding the entry name and, sometimes, one caption line.
 *
 * Deliberately unaware of the launcher theme's font and size. The catalog is
 * system chrome, exactly as in Swift, where the picker's List inherited nothing
 * from `Theme` beyond the window's color scheme.
 */

/**
 * Mirrors `CatalogPickerView.caption(for:)`. The order matters and is the whole
 * point: a note WINS over the unverified warning, so an entry that is both
 * noted and unverified shows only its note. Photos and Calendar are noted and
 * verified; YouTube Music and Notion are unverified and carry notes that already
 * say so in their own words.
 */
export function captionFor(entry: CatalogEntry, unverified: string): string | null {
  if (entry.note !== undefined) return entry.note;
  if (!entry.verified) return unverified;
  return null;
}

export interface CatalogRowProps {
  entry: CatalogEntry;
  /**
   * Already localized by the caller. The row is deliberately not the place that
   * decides what an entry is called: `catalog.tsx` needs the same value to hand
   * back to the form, so resolving it twice would be two chances to disagree.
   */
  name: string;
  /** Swift's `.tint(.primary)`: the name reads as a label, not as a blue button. */
  labelColor: string;
  captionColor: string;
}

export function CatalogRow({ entry, name, labelColor, captionColor }: CatalogRowProps) {
  const s = useStrings();
  // The eight `note` strings are English in every language, by decision: they
  // name actions and URL schemes that have to be matched verbatim against what
  // Apple shows. Only the unverified warning is translated.
  const caption = captionFor(entry, s.catalogUnverified);

  return (
    <View style={styles.column}>
      <Text style={[styles.name, { color: labelColor }]}>{name}</Text>
      {caption !== null && (
        <Text style={[styles.caption, { color: captionColor }]}>{caption}</Text>
      )}
    </View>
  );
}

const styles = StyleSheet.create({
  column: {
    alignItems: 'flex-start',
    gap: 2,
  },
  name: {
    fontSize: 17,
  },
  caption: {
    fontSize: 12,
  },
});
