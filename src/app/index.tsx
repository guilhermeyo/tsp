import { SymbolView } from 'expo-symbols';
import { Stack, useRouter, useTheme as useNavigationTheme } from 'expo-router';
import { useMemo, useState } from 'react';
import { Pressable, StyleSheet, Text, View } from 'react-native';
import { Gesture } from 'react-native-gesture-handler';
import ReorderableList from 'react-native-reorderable-list';
import type { ReorderableListReorderEvent } from 'react-native-reorderable-list';
import { useSafeAreaInsets } from 'react-native-safe-area-context';

import { AppRow } from '@/components/AppRow';
import { EmptyState } from '@/components/EmptyState';
import type { LauncherApp } from '@/domain/types';
import { useLauncherStore } from '@/store/LauncherStore';

/**
 * SCREEN 1. The whole app is this list plus three sheets hanging off its
 * toolbar.
 *
 * Toolbar shape is inherited from the original, where it was assembled from two
 * places: `AppListView` contributed Edit (leading) and plus (`.primaryAction`,
 * which is trailing on iOS), and `RootView` contributed the gear. Net result is
 * Edit on the left, plus then gear on the right.
 */
/**
 * Height of an EXPANDED iOS large-title navigation bar, below the status bar:
 * 44pt of standard bar plus 52pt of large title.
 *
 * Hardcoded on purpose. `useHeaderHeight()` cannot be used here: for a large
 * title it reports the COLLAPSED height and then receives debounced native
 * updates as the title shrinks, so a padding driven by it would move while the
 * user scrolls.
 */
const LARGE_TITLE_HEADER_HEIGHT = 96;

export default function AppListScreen() {
  const store = useLauncherStore();
  const { colors } = useNavigationTheme();
  const router = useRouter();
  const insets = useSafeAreaInsets();
  const [editing, setEditing] = useState(false);

  const apps = store.config.apps;

  /**
   * The list's drag gesture, owned here so it can be switched off outside Edit
   * mode. Two things depend on that.
   *
   * Fidelity: the original has no long-press-to-drag-anytime. Dragging exists
   * only while `EditButton` is active.
   *
   * Mechanics: this pan sits on the list container and activates on any small
   * movement, so left alone it would win the race against the per-row
   * swipe-to-delete pan and quietly break it. Disabling it outside Edit mode,
   * and disabling the swipe inside Edit mode, makes the two interactions
   * mutually exclusive by construction rather than by gesture arbitration.
   */
  const dragGesture = useMemo(() => Gesture.Pan().enabled(editing), [editing]);

  function openForm(id?: string): void {
    router.push(
      id === undefined
        ? '/(modals)/app-form'
        : { pathname: '/(modals)/app-form', params: { id } }
    );
  }

  function handleReorder({ from, to }: ReorderableListReorderEvent): void {
    // Committed on drop, with no Done step: array order IS the widget's
    // render order, and the store persists and reloads the timeline for us.
    store.move(from, to);
  }

  return (
    <View style={[styles.screen, { backgroundColor: colors.background }]}>
      <Stack.Screen
        options={{
          // Rendered even when the list is empty, where it toggles a mode with
          // nothing to show. That is the original's behavior, not an oversight.
          headerLeft: () => (
            <Pressable onPress={() => setEditing((value) => !value)} hitSlop={8}>
              <Text
                style={[
                  styles.editLabel,
                  { color: colors.primary, fontWeight: editing ? '600' : '400' },
                ]}
              >
                {editing ? 'Done' : 'Edit'}
              </Text>
            </Pressable>
          ),
          headerRight: () => (
            <View style={styles.headerActions}>
              <Pressable onPress={() => openForm()} hitSlop={8} accessibilityLabel="Add app">
                <SymbolView name="plus" size={22} tintColor={colors.primary} style={styles.icon} />
              </Pressable>
              <Pressable
                onPress={() => router.push('/(modals)/appearance')}
                hitSlop={8}
                accessibilityLabel="Appearance"
              >
                <SymbolView
                  name="gearshape"
                  size={22}
                  tintColor={colors.primary}
                  style={styles.icon}
                />
              </Pressable>
            </View>
          ),
        }}
      />

      {apps.length === 0 ? (
        <EmptyState />
      ) : (
        <ReorderableList
          data={apps}
          keyExtractor={(app: LauncherApp) => app.id}
          onReorder={handleReorder}
          panGesture={dragGesture}
          dragEnabled={editing}
          // The large title's vertical offset lives in the CONTENT here, not in
          // a UIKit content inset, and that is load-bearing.
          //
          // react-native-reorderable-list has no notion of contentInset (grep
          // the package: zero hits) and models scroll position as a shared value
          // seeded to 0, so it assumes a resting contentOffset.y of 0. Under a
          // large title, react-native-screens lays the content out at screen
          // y=0 and UIKit parks contentOffset.y at about -155 via
          // adjustedContentInset. The library disables scrolling when a drag
          // starts, UIKit then recomputes the "automatic" inset to zero, and the
          // whole content view slams up by the header height, painting every row
          // over the nav bar. The dragged cell alone gets compensated back down,
          // which is why one row stays put with a gap above it.
          //
          // Padding cannot be recomputed out from under us, so resting offset is
          // a true 0 and there is nothing left to collapse. The title still
          // collapses on scroll because UIKit drives that from contentOffset.
          contentInsetAdjustmentBehavior="never"
          contentContainerStyle={{ paddingTop: insets.top + LARGE_TITLE_HEADER_HEIGHT }}
          renderItem={({ item, index }) => (
            <AppRow
              app={item}
              editing={editing}
              onPress={() => openForm(item.id)}
              onDelete={() => store.removeAt(index)}
            />
          )}
        />
      )}
    </View>
  );
}

const styles = StyleSheet.create({
  screen: {
    flex: 1,
  },
  headerActions: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 20,
  },
  icon: {
    width: 22,
    height: 22,
  },
  editLabel: {
    fontSize: 17,
  },
});
