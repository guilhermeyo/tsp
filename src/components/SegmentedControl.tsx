import { useEffect, useRef, useState } from 'react';
import type { LayoutChangeEvent } from 'react-native';
import { Animated, Pressable, StyleSheet, Text, View } from 'react-native';

const TRACK_PADDING = 2;
const THUMB_DURATION_MS = 180;

export interface SegmentedControlProps<T extends string> {
  options: readonly T[];
  labels: Readonly<Record<T, string>>;
  value: T;
  onChange: (next: T) => void;
  /** The launcher theme's Dark switch, not the system appearance. */
  isDark: boolean;
  accessibilityLabel?: string;
}

/**
 * A three-segment picker, hand-rolled.
 *
 * Not `@react-native-segmented-control/segmented-control`: that package was
 * last published in December 2024, and a stale native dependency is a poor
 * trade for one control made of three Pressables and a sliding rectangle.
 */
export function SegmentedControl<T extends string>({
  options,
  labels,
  value,
  onChange,
  isDark,
  accessibilityLabel,
}: SegmentedControlProps<T>) {
  const [trackWidth, setTrackWidth] = useState(0);
  const selected = Math.max(0, options.indexOf(value));

  // Driven in segment INDEX units, so the interpolation below survives a layout
  // change without needing to be rebuilt.
  const position = useRef(new Animated.Value(selected)).current;

  useEffect(() => {
    Animated.timing(position, {
      toValue: selected,
      duration: THUMB_DURATION_MS,
      // transform-only, so it can run entirely on the UI thread.
      useNativeDriver: true,
    }).start();
  }, [position, selected]);

  const segmentWidth = trackWidth > 0 ? (trackWidth - TRACK_PADDING * 2) / options.length : 0;

  function handleLayout(event: LayoutChangeEvent): void {
    setTrackWidth(event.nativeEvent.layout.width);
  }

  return (
    <View
      accessibilityRole="tablist"
      accessibilityLabel={accessibilityLabel}
      onLayout={handleLayout}
      style={[
        styles.track,
        { backgroundColor: isDark ? 'rgba(120, 120, 128, 0.32)' : 'rgba(120, 120, 128, 0.12)' },
      ]}
    >
      <Animated.View
        // Purely decorative: it sits under the labels and is driven by state.
        pointerEvents="none"
        style={[
          styles.thumb,
          {
            width: segmentWidth,
            backgroundColor: isDark ? '#636366' : '#FFFFFF',
            transform: [
              {
                translateX: position.interpolate({
                  inputRange: [0, 1],
                  outputRange: [0, segmentWidth],
                }),
              },
            ],
          },
        ]}
      />
      {options.map((option) => (
        <Pressable
          key={option}
          accessibilityRole="tab"
          accessibilityState={{ selected: option === value }}
          // Discrete taps only. A slider would fire on every frame of a drag and
          // each fire writes the whole config and reloads every widget timeline;
          // three tap targets cannot thrash that budget.
          onPress={() => onChange(option)}
          style={styles.segment}
        >
          <Text style={[styles.label, { color: isDark ? '#FFFFFF' : '#000000' }]}>
            {labels[option]}
          </Text>
        </Pressable>
      ))}
    </View>
  );
}

const styles = StyleSheet.create({
  track: {
    flexDirection: 'row',
    alignSelf: 'stretch',
    padding: TRACK_PADDING,
    borderRadius: 9,
  },
  thumb: {
    position: 'absolute',
    top: TRACK_PADDING,
    left: TRACK_PADDING,
    bottom: TRACK_PADDING,
    borderRadius: 7,
    shadowColor: '#000000',
    shadowOpacity: 0.12,
    shadowRadius: 2,
    shadowOffset: { width: 0, height: 1 },
  },
  segment: {
    flex: 1,
    alignItems: 'center',
    justifyContent: 'center',
    paddingVertical: 6,
  },
  label: {
    fontSize: 13,
    fontWeight: '500',
  },
});
