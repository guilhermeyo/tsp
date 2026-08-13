import { Stack, useRouter } from 'expo-router';
import { Pressable, ScrollView, StyleSheet, Text, View } from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';

import { CatalogRow } from '@/components/CatalogRow';
import { byCategory, categoryLabel, entryName } from '@/domain/catalog';
import type { CatalogEntry } from '@/domain/catalog';
import { useStrings } from '@/i18n/useStrings';
import { useLauncherStore, useTheme } from '@/store/LauncherStore';

/**
 * SCREEN 3 — the catalog picker. Twin of `CatalogPickerView.swift`.
 *
 * It rises as a sheet ON TOP of the still-open form sheet and returns to it.
 * Picking an entry PREFILLS the form's two fields and nothing else: it never
 * touches the store, never adds the app, never persists. The user still has to
 * tap Add or Save. Cancel leaves the form exactly as the user left it.
 *
 * THE RETURN CHANNEL, which the form consumes:
 *
 *   import { catalogSelection } from '@/app/(modals)/catalog';
 *
 *   useEffect(() => catalogSelection.subscribe(({ name, urlString }) => {
 *     setName(name);
 *     setURL(urlString);
 *   }), []);
 *
 * Router params were the obvious alternative and are wrong here. A param set on
 * the way back would still be sitting on the form's route afterwards, so any
 * remount -- a re-render triggered by navigation, a Fast Refresh, the form being
 * re-entered -- would replay the last pick and silently clobber whatever the
 * user had typed since. This channel is an event, not state: it fires once, at
 * the moment of the tap, and leaves nothing behind.
 */

export interface CatalogSelection {
  name: string;
  urlString: string;
}

/**
 * One slot, not a list. Exactly one form is on screen at a time, and a stale
 * listener from a dismissed form must never receive a later pick -- an array of
 * subscribers would let a form that was swiped away keep listening until its
 * cleanup ran, which on iOS happens after the dismissal animation.
 */
let listener: ((selection: CatalogSelection) => void) | null = null;

export const catalogSelection = {
  pick(entry: CatalogSelection): void {
    listener?.({ name: entry.name, urlString: entry.urlString });
  },

  /** Returns the unsubscribe function, shaped for a bare `useEffect` return. */
  subscribe(fn: (selection: CatalogSelection) => void): () => void {
    listener = fn;
    return () => {
      // Only clear the slot if nobody has claimed it since, so a late cleanup
      // cannot unsubscribe the form that replaced us.
      if (listener === fn) listener = null;
    };
  },
};

/**
 * The picker is a plain iOS inset-grouped list, which React Native does not
 * ship, so the chrome is drawn by hand. The values are the system ones: 16pt
 * card margin, 44pt minimum row height, hairline separators inset to the text.
 *
 * These follow the launcher's own Dark toggle rather than the OS appearance,
 * because `theme.isDark` is what SwiftUI's `.preferredColorScheme` drove at the
 * WindowGroup, and every sheet inherited it.
 */
function palette(isDark: boolean) {
  return isDark
    ? {
        page: '#000000',
        card: '#1C1C1E',
        pressed: '#2C2C2E',
        label: '#FFFFFF',
        secondary: 'rgba(235,235,245,0.6)',
        separator: 'rgba(84,84,88,0.65)',
        accent: '#0A84FF',
      }
    : {
        page: '#F2F2F7',
        card: '#FFFFFF',
        pressed: '#D1D1D6',
        label: '#000000',
        secondary: 'rgba(60,60,67,0.6)',
        separator: 'rgba(60,60,67,0.29)',
        accent: '#007AFF',
      };
}

export default function CatalogScreen() {
  const theme = useTheme();
  const router = useRouter();
  const insets = useSafeAreaInsets();
  const s = useStrings();
  const { language } = useLauncherStore().config;
  const colors = palette(theme.isDark);

  function select(entry: CatalogEntry, name: string): void {
    // The LOCALIZED name is handed over, not `entry.name`. An app's name is
    // user data in this app -- the six bundled defaults are Portuguese for the
    // same reason -- so prefilling "Messages" after the user tapped a row
    // reading "Mensagens" would contradict the tap. The url is the wire value
    // and is handed over untouched.
    //
    // Order copied from Swift: hand the entry over first, dismiss second. The
    // form is still mounted underneath, so it receives the values before the
    // sheet starts animating away.
    catalogSelection.pick({ name, urlString: entry.urlString });
    router.back();
  }

  return (
    <View style={[styles.page, { backgroundColor: colors.page }]}>
      <Stack.Screen
        options={{
          title: s.catalogTitle,
          // Inline, never large: `.navigationBarTitleDisplayMode(.inline)`.
          // Already the default, stated because the list screen opts INTO large.
          headerLargeTitleEnabled: false,
          // `headerLeft` REPLACES the stack's back button (opting back in would
          // take `headerBackVisible: true`). That is what we want: both controls
          // dismiss, but the original showed exactly one leading item labelled
          // Cancel, and a chevron would read as "go back having applied
          // something", which is not what Cancel does here.
          headerLeft: () => (
            <Pressable onPress={() => router.back()} hitSlop={12}>
              <Text style={[styles.headerButton, { color: colors.accent }]}>{s.commonCancel}</Text>
            </Pressable>
          ),
        }}
      />

      <ScrollView
        contentContainerStyle={[styles.content, { paddingBottom: insets.bottom + 24 }]}
        contentInsetAdjustmentBehavior="automatic"
      >
        {/*
          `section.category` and `entry.name` stay the ENGLISH keys throughout:
          they are the grouping key and the entry identity, and only their
          rendering is localized. Both lookups happen here rather than inside
          `CatalogRow`, so the row renders whatever it is handed and never has
          to know which language it is in.
        */}
        {byCategory.map((section) => (
          <View key={section.category}>
            <Text style={[styles.sectionHeader, { color: colors.secondary }]}>
              {categoryLabel(section.category, language)}
            </Text>

            <View style={[styles.card, { backgroundColor: colors.card }]}>
              {section.entries.map((entry, index) => {
                const name = entryName(entry, language);
                return (
                  <View key={entry.id}>
                    {index > 0 && (
                      <View style={[styles.separator, { backgroundColor: colors.separator }]} />
                    )}
                    <Pressable
                      onPress={() => select(entry, name)}
                      style={({ pressed }) => [
                        styles.row,
                        pressed ? { backgroundColor: colors.pressed } : null,
                      ]}
                    >
                      <CatalogRow
                        entry={entry}
                        name={name}
                        labelColor={colors.label}
                        captionColor={colors.secondary}
                      />
                    </Pressable>
                  </View>
                );
              })}
            </View>
          </View>
        ))}
      </ScrollView>
    </View>
  );
}

const styles = StyleSheet.create({
  page: {
    flex: 1,
  },
  content: {
    paddingHorizontal: 16,
    paddingTop: 8,
  },
  headerButton: {
    fontSize: 17,
  },
  sectionHeader: {
    fontSize: 13,
    paddingLeft: 16,
    paddingTop: 24,
    paddingBottom: 6,
  },
  card: {
    borderRadius: 10,
    overflow: 'hidden',
  },
  row: {
    minHeight: 44,
    justifyContent: 'center',
    paddingHorizontal: 16,
    paddingVertical: 11,
  },
  separator: {
    height: StyleSheet.hairlineWidth,
    marginLeft: 16,
  },
});
