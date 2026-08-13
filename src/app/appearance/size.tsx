import { Stack, useRouter, useTheme as useNavigationTheme } from 'expo-router';
import { SymbolView } from 'expo-symbols';
import { Fragment } from 'react';
import { Pressable, ScrollView, StyleSheet, Text, View } from 'react-native';

import { TEXT_SIZES } from '@/domain/types';
import { useStrings } from '@/i18n/useStrings';
import { useLauncherStore } from '@/store/LauncherStore';

const SECTION_INSET = 20;
const ROW_PADDING = 16;

/** The list SwiftUI pushes when a default-styled `Picker` row is tapped. */
export default function SizeScreen() {
  const store = useLauncherStore();
  const theme = store.config.theme;
  const router = useRouter();
  const { colors } = useNavigationTheme();
  const s = useStrings();

  return (
    <>
      <Stack.Screen options={{ title: s.sectionSize }} />
      <ScrollView
        contentInsetAdjustmentBehavior="automatic"
        style={{ backgroundColor: colors.background }}
        contentContainerStyle={styles.content}
      >
        <View style={[styles.card, { backgroundColor: colors.card }]}>
          {TEXT_SIZES.map((size, index) => (
            <Fragment key={size}>
              {index > 0 && (
                <View style={[styles.separator, { backgroundColor: colors.border }]} />
              )}
              <Pressable
                accessibilityRole="button"
                accessibilityState={{ selected: size === theme.size }}
                style={styles.row}
                onPress={() => {
                  store.updateTheme({ size });
                  router.back();
                }}
              >
                {/*
                  Deliberately NOT previewed at its own point size: the original
                  showed plain rows, and 44pt "Extra Large" would tower over the
                  form. The preview card on the previous screen is where size is
                  meant to be judged.
                */}
                <Text style={[styles.rowLabel, { color: colors.text }]}>{s.sizeLabels[size]}</Text>
                {size === theme.size && (
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
