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
import { useStrings } from '@/i18n/useStrings';
import { useTheme } from '@/store/LauncherStore';
import { fontFamilyFor } from '@/theme/fonts';
import {
  LIST_LINE_HEIGHT,
  LIST_POINT_SIZE,
  flexAlign,
  textAlign,
  textColor,
  trackingFor,
} from '@/theme/tokens';

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
  /**
   * Open the edit form. Live in BOTH modes: Edit is where a user goes to change
   * the list, so a row that refuses to open there sends them out of Edit to
   * rename and back into it to reorder.
   */
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
  const s = useStrings();
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
        // Not disabled in Edit mode. Nothing else has to change for that: the
        // minus and the grabber are nested Pressables, and a nested one wins the
        // responder over its parent, so only the middle of the row opens the
        // form. The list's pan is live in Edit mode and can still steal a tap
        // that drifts, which is the same forgiveness as tapping a row on a list
        // that is scrolling.
        onPress={onPress}
        onLayout={handleLayout}
        // Opaque: this is what the red slides out from underneath.
        style={[styles.row, { backgroundColor: colors.card }]}
      >
        {editing ? (
          // A pattern rather than a label plus the name: Japanese is verb-final,
          // so "Delete {name}" cannot be assembled by concatenation. The name
          // itself is the user's own text and is never translated.
          <Pressable onPress={onDelete} hitSlop={8} accessibilityLabel={s.a11yDeleteApp(app.name)}>
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
            // The widget shrinks a name that does not fit; this list used to
            // wrap it instead, so the same app looked like two different apps
            // in the two places. One line plus shrink-to-fit, same floor as
            // `.minimumScaleFactor(0.5)`, makes them agree. On iOS
            // `adjustsFontSizeToFit` is inert without `numberOfLines`.
            numberOfLines={1}
            adjustsFontSizeToFit
            minimumFontScale={0.5}
            style={{
              fontFamily: fontFamilyFor(theme.font),
              fontSize: LIST_POINT_SIZE[theme.size],
              // Semibold, matching `LauncherRowLabel` in both languages. It was
              // missing here, so the list rendered regular directly beneath a
              // semibold preview of the same names and the pair looked like two
              // unrelated fonts. Weight is fixed everywhere; the theme owns
              // family and size only.
              fontWeight: '600',
              lineHeight: LIST_LINE_HEIGHT[theme.size],
              letterSpacing: trackingFor(theme.font, LIST_POINT_SIZE[theme.size]),
              color: textColor(theme),
              // Both projections are needed: `alignItems` places the text box,
              // `textAlign` places the glyphs inside it once shrink-to-fit has
              // left the box wider than the line it holds.
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
          <Pressable onPressIn={drag} hitSlop={8} accessibilityLabel={s.a11yReorderApp(app.name)}>
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
  // Read here rather than passed down from `AppRow`: this is a real component
  // element inside the swipeable's render prop, so it re-renders with the store
  // on its own and the label needs no plumbing through `renderRightActions`.
  const s = useStrings();

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
      <Text style={styles.actionLabel}>{s.commonDelete}</Text>
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
