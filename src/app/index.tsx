import { SymbolView } from 'expo-symbols';
import { Stack, useRouter, useTheme as useNavigationTheme } from 'expo-router';
import { useMemo, useState } from 'react';
import { Pressable, StyleSheet, Text, View } from 'react-native';
import { Gesture } from 'react-native-gesture-handler';
import ReorderableList from 'react-native-reorderable-list';
import type { ReorderableListReorderEvent } from 'react-native-reorderable-list';

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
export default function AppListScreen() {
  const store = useLauncherStore();
  const { colors } = useNavigationTheme();
  const router = useRouter();
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
          // Lets the native large title collapse as the list scrolls.
          contentInsetAdjustmentBehavior="automatic"
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
