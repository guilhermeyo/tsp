import { SymbolView } from 'expo-symbols';
import { Stack, useRouter, useTheme as useNavigationTheme } from 'expo-router';
import { useMemo, useState } from 'react';
import { Pressable, StyleSheet, Text, View } from 'react-native';
import { Gesture } from 'react-native-gesture-handler';
import ReorderableList from 'react-native-reorderable-list';
import type { ReorderableListReorderEvent } from 'react-native-reorderable-list';
import { useSafeAreaInsets } from 'react-native-safe-area-context';

import { AppRow } from '@/components/AppRow';
import { SECTION_INSET } from '@/components/DisclosureRow';
import { EmptyState } from '@/components/EmptyState';
import { WidgetPreviewCard } from '@/components/WidgetPreviewCard';
import type { LauncherApp } from '@/domain/types';
import { useStrings } from '@/i18n/useStrings';
import { useLauncherStore } from '@/store/LauncherStore';

/**
 * The app list, pushed from the hub.
 *
 * This WAS the root screen, and its toolbar was inherited from the original,
 * where it was assembled from two places: `AppListView` contributed Edit
 * (leading) and plus (`.primaryAction`, which is trailing on iOS), and
 * `RootView` contributed the gear. The gear is gone -- Appearance is a section
 * of the hub now, not a thing hidden behind an icon in the corner of the list.
 * Edit on the left and plus on the right are unchanged.
 *
 * The widget preview lives here too, above the rows. It used to sit on the hub,
 * where it was the biggest thing on a screen that is otherwise a menu; here it
 * is next to the very list it renders, so adding, renaming and reordering all
 * show their result without leaving the screen.
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

/**
 * The preview card's inset, matching every other screen that shows a widget
 * mock. `SECTION_INSET + PREVIEW_INSET` = 32pt, which is the width a systemLarge
 * widget actually occupies on an iPhone; see the note in DisclosureRow. The same
 * 12 is used vertically, so the card sits in the same rhythm here as on
 * Appearance.
 */
const PREVIEW_INSET = 12;

export default function AppListScreen() {
  const store = useLauncherStore();
  const s = useStrings();
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
          title: s.sectionApps,
          // NOT negotiable, and not a style choice. The large title is what the
          // hardcoded LARGE_TITLE_HEADER_HEIGHT above compensates for; switching
          // to an inline title leaves the padding 52pt too tall and the list
          // resting below its own header, with nothing on screen to explain it.
          headerLargeTitleEnabled: true,
          // `headerLeft` REPLACES the system back button: it renders into the
          // header's left view, and react-native-screens only supplements the
          // chevron with that view when `leftItemsSupplementBackButton` is set.
          // expo-router computes that flag from `headerBackVisible` on iOS, so
          // without this line the screen is a dead end -- Edit sits where the
          // chevron would be and the only way out is the home gesture.
          headerBackVisible: true,
          // Chevron only. The back title defaults to the previous screen's
          // title, and "The Simple Phone" next to Edit is wider than the two of
          // them have room for on a large-title bar.
          headerBackButtonDisplayMode: 'minimal',
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
                {editing ? s.appsDone : s.appsEdit}
              </Text>
            </Pressable>
          ),
          headerRight: () => (
            <Pressable onPress={() => openForm()} hitSlop={8} accessibilityLabel={s.a11yAddApp}>
              <SymbolView name="plus" size={22} tintColor={colors.primary} style={styles.icon} />
            </Pressable>
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
          //
          // The preview below goes through `ListHeaderComponent` for the same
          // reason, and it is the only insertion point that cannot disturb any
          // of this: it adds CONTENT-space offset above row 0, exactly like the
          // padding already does, and touches no inset. Every cell writes its
          // own layout y into `itemOffset[index]`, and both the drag math and
          // the drop math subtract `flatListScrollOffsetXY` from it, so the two
          // live in one coordinate space and a constant added to every cell
          // cancels out. Rendering the card OUTSIDE the list would not be safe:
          // react-native-screens finds the scroll view by walking `subviews[0]`,
          // so a sibling above the list would cost the large title its collapse
          // and move the offset this constant was calibrated against.
          contentInsetAdjustmentBehavior="never"
          ListHeaderComponent={
            // A plain View, not a Pressable: it must not compete with the list's
            // pan for the finger while Edit mode is on.
            <View style={styles.preview}>
              <WidgetPreviewCard config={store.config} />
            </View>
          }
          contentContainerStyle={{
            paddingTop: insets.top + LARGE_TITLE_HEADER_HEIGHT,
            // `never` switches off the BOTTOM inset too, so the last row would
            // otherwise end under the home indicator now that the list is long
            // enough to scroll.
            paddingBottom: insets.bottom + PREVIEW_INSET,
          }}
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
  preview: {
    paddingHorizontal: SECTION_INSET + PREVIEW_INSET,
    paddingVertical: PREVIEW_INSET,
  },
  icon: {
    width: 22,
    height: 22,
  },
  editLabel: {
    fontSize: 17,
  },
});
