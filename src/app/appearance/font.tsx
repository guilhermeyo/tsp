import { Stack, useRouter, useTheme as useNavigationTheme } from 'expo-router';
import { SymbolView } from 'expo-symbols';
import { Fragment } from 'react';
import { Pressable, ScrollView, StyleSheet, Text, View } from 'react-native';

import { FONT_CHOICES } from '@/domain/types';
import { useStrings } from '@/i18n/useStrings';
import { useLauncherStore } from '@/store/LauncherStore';
import { fontFamilyFor } from '@/theme/fonts';

const SECTION_INSET = 20;
const ROW_PADDING = 16;

/** The list SwiftUI pushes when a default-styled `Picker` row is tapped. */
export default function FontScreen() {
  const store = useLauncherStore();
  const theme = store.config.theme;
  const router = useRouter();
  const { colors } = useNavigationTheme();
  const s = useStrings();

  return (
    <>
      <Stack.Screen options={{ title: s.sectionFont }} />
      <ScrollView
        contentInsetAdjustmentBehavior="automatic"
        style={{ backgroundColor: colors.background }}
        contentContainerStyle={styles.content}
      >
        <View style={[styles.card, { backgroundColor: colors.card }]}>
          {FONT_CHOICES.map((choice, index) => (
            <Fragment key={choice}>
              {index > 0 && (
                <View style={[styles.separator, { backgroundColor: colors.border }]} />
              )}
              <Pressable
                accessibilityRole="button"
                accessibilityState={{ selected: choice === theme.font }}
                style={styles.row}
                onPress={() => {
                  // Selecting the current value still writes and still reloads
                  // every widget timeline. That is what the Swift binding did,
                  // and the store deliberately allocates a new config for it.
                  store.updateTheme({ font: choice });
                  router.back();
                }}
              >
                {/*
                  Each option is drawn in the face it selects, so the choice is
                  legible before it is made.

                  That preview is weaker in Japanese and it is not a bug: none of
                  the four faces ships CJK glyphs, so iOS substitutes the system
                  font per character and the four labels look alike. The widget
                  preview one screen back renders the user's own app names, which
                  is where the difference is actually visible.
                */}
                <Text
                  style={[styles.rowLabel, { color: colors.text, fontFamily: fontFamilyFor(choice) }]}
                >
                  {s.fontLabels[choice]}
                </Text>
                {choice === theme.font && (
                  <SymbolView
                    name="checkmark"
                    size={16}
                    weight="semibold"
                    tintColor={colors.primary}
                    style={styles.checkmark}
                  />
                )}
              </Pressable>
            </Fragment>
          ))}
        </View>
      </ScrollView>
    </>
  );
}

const styles = StyleSheet.create({
  content: {
    paddingTop: 24,
    paddingBottom: 32,
  },
  card: {
    marginHorizontal: SECTION_INSET,
    borderRadius: 10,
    overflow: 'hidden',
  },
  row: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    minHeight: 44,
    paddingHorizontal: ROW_PADDING,
    paddingVertical: 8,
    gap: 12,
  },
  rowLabel: {
    fontSize: 17,
  },
  checkmark: {
    width: 16,
    height: 16,
  },
  separator: {
    height: StyleSheet.hairlineWidth,
    marginLeft: ROW_PADDING,
  },
});
