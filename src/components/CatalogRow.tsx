import { StyleSheet, Text, View } from 'react-native';

import type { CatalogEntry } from '@/domain/catalog';

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
export function captionFor(entry: CatalogEntry): string | null {
  if (entry.note !== undefined) return entry.note;
  if (!entry.verified) return 'Unverified — may not open reliably.';
  return null;
}

export interface CatalogRowProps {
  entry: CatalogEntry;
  /** Swift's `.tint(.primary)`: the name reads as a label, not as a blue button. */
  labelColor: string;
  captionColor: string;
}

export function CatalogRow({ entry, labelColor, captionColor }: CatalogRowProps) {
  const caption = captionFor(entry);

  return (
    <View style={styles.column}>
      <Text style={[styles.name, { color: labelColor }]}>{entry.name}</Text>
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
