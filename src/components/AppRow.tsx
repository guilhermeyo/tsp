import { SymbolView } from 'expo-symbols';
import { useTheme as useNavigationTheme } from 'expo-router';
import { useRef } from 'react';
import { Pressable, StyleSheet, Text, View } from 'react-native';
import type { LayoutChangeEvent } from 'react-native';
import ReanimatedSwipeable from 'react-native-gesture-handler/ReanimatedSwipeable';
import type { SharedValue } from 'react-native-reanimated';
import { useAnimatedReaction, useSharedValue } from 'react-native-reanimated';
import { useReorderableDrag } from 'react-native-reorderable-list';

import type { LauncherApp } from '@/domain/types';
import { useTheme } from '@/store/LauncherStore';
import { fontFamilyFor } from '@/theme/fonts';
import { LIST_POINT_SIZE, flexAlign, textAlign, textColor } from '@/theme/tokens';

/** Width of the revealed Delete panel, matching the iOS list action button. */
const ACTION_WIDTH = 88;

/**
 * Fraction of the row's width the finger must travel for a release to count as
 * a full swipe. iOS uses roughly three quarters of the row; a little less feels
 * right here because the rows are short.
 */
const FULL_SWIPE_RATIO = 0.6;

/** `UIColor.systemRed`, whose dark variant is a slightly lighter red. */
function destructiveColor(isDark: boolean): string {
  return isDark ? '#FF453A' : '#FF3B30';
}

interface AppRowProps {
  app: LauncherApp;
  /** Edit mode swaps swipe-to-delete for the minus/grabber chrome, as `EditButton` does. */
  editing: boolean;
  /** Open the edit form. Never called while editing: the row is not tappable then. */
  onPress: () => void;
  onDelete: () => void;
}

/**
 * One launcher row: the name and nothing else.
 *
 * No URL, no icon, no chevron, no subtitle, no separator. The original hides
 * separators explicitly rather than by accident, so none are drawn here either.
 */
export function AppRow({ app, editing, onPress, onDelete }: AppRowProps) {
  const theme = useTheme();
  const { colors } = useNavigationTheme();

  // Only valid inside a ReorderableList cell -- the hook reads the cell's
  // context and throws outside it. Calling it here (rather than passing a
  // handle down from renderItem) is required: renderItem runs during the
  // LIST's render, so a hook called there would read the list's context.
  const drag = useReorderableDrag();

  const rowWidth = useRef(0);

  // How far the finger has dragged, at its furthest, during the current swipe.
  // Peak rather than current because the decision is made on release, by which
  // point the row is already springing back toward the open stop.
  const peakSwipe = useSharedValue(0);

  const destructive = destructiveColor(theme.isDark);

  function handleLayout(event: LayoutChangeEvent): void {
    rowWidth.current = event.nativeEvent.layout.width;
  }

  function handleWillOpen(): void {
    if (rowWidth.current === 0) return;
    // A full swipe deletes with no confirmation and no undo, exactly like the
    // partial swipe's Delete button and the edit-mode minus. All three delete
    // paths in the original are unconfirmed; do not add an Alert to any of them.
    if (peakSwipe.value >= rowWidth.current * FULL_SWIPE_RATIO) {
      onDelete();
    }
  }

  return (
    <ReanimatedSwipeable
      enabled={!editing}
      rightThreshold={ACTION_WIDTH / 2}
      onSwipeableWillOpen={handleWillOpen}
      // The action panel is a fixed 88pt, but a full swipe drags the row much
      // further than that. Painting the container red fills the gap, so the
      // overshoot reads as one continuous red field instead of a red button
      // followed by a hole.
      containerStyle={{ backgroundColor: destructive }}
      renderRightActions={(_progress, translation) => (
        <DeleteAction
          translation={translation}
          peak={peakSwipe}
          color={destructive}
          onPress={onDelete}
        />
      )}
    >
      <Pressable
        onPress={onPress}
        disabled={editing}
        onLayout={handleLayout}
        // Opaque: this is what the red slides out from underneath.
        style={[styles.row, { backgroundColor: colors.card }]}
      >
        {editing ? (
          <Pressable onPress={onDelete} hitSlop={8} accessibilityLabel={`Delete ${app.name}`}>
            <SymbolView
              name="minus.circle.fill"
              size={22}
              tintColor={destructive}
              style={styles.chrome}
            />
          </Pressable>
        ) : null}

        <View style={[styles.nameBox, { alignItems: flexAlign(theme.alignment) }]}>
          <Text
            style={{
              fontFamily: fontFamilyFor(theme.font),
              fontSize: LIST_POINT_SIZE[theme.size],
              color: textColor(theme),
              // Both projections are needed: `alignItems` places the text box,
              // `textAlign` places the lines inside it once a long name wraps.
              textAlign: textAlign(theme.alignment),
            }}
          >
            {app.name}
          </Text>
        </View>

        {editing ? (
          // `onPressIn`, not `onPress`: the grabber must take over the moment
          // the finger lands, or the drag would only begin after the finger
          // lifted. `drag()` is a no-op unless the list has `dragEnabled`.
          <Pressable onPressIn={drag} hitSlop={8} accessibilityLabel={`Reorder ${app.name}`}>
            <SymbolView
              name="line.3.horizontal"
              size={22}
              tintColor={colors.border}
              style={styles.chrome}
            />
          </Pressable>
        ) : null}
      </Pressable>
    </ReanimatedSwipeable>
  );
}

interface DeleteActionProps {
  /** The swipeable's own horizontal offset. Negative while the right panel shows. */
  translation: SharedValue<number>;
  peak: SharedValue<number>;
  color: string;
  onPress: () => void;
}

/**
 * The revealed Delete button, and the only place the swipe distance is legible.
 *
 * `translation` is handed out by the swipeable's render prop, so the peak has to
 * be recorded from in here. It keeps extending past the panel width for as long
 * as the finger drags (that is the overshoot behavior), which is what separates
 * a full swipe from a partial one.
 */
function DeleteAction({ translation, peak, color, onPress }: DeleteActionProps) {
  useAnimatedReaction(
    () => translation.value,
    (current) => {
      const dragged = -current;
      if (dragged <= 0) {
        // Back at rest. Resetting on the UI thread, rather than from a JS-side
        // gesture callback, keeps the peak from carrying into the next swipe.
        peak.value = 0;
        return;
      }
      if (dragged > peak.value) {
        peak.value = dragged;
      }
    }
  );

  return (
    <Pressable onPress={onPress} style={[styles.action, { backgroundColor: color }]}>
      <Text style={styles.actionLabel}>Delete</Text>
    </Pressable>
  );
}

const styles = StyleSheet.create({
  row: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 12,
    paddingHorizontal: 20,
    paddingVertical: 12,
  },
  nameBox: {
    flex: 1,
  },
  chrome: {
    width: 22,
    height: 22,
  },
  action: {
    width: ACTION_WIDTH,
    alignItems: 'center',
    justifyContent: 'center',
  },
  actionLabel: {
    color: '#FFFFFF',
    fontSize: 17,
  },
});
