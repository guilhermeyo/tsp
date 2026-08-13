import { Stack, useRouter, useTheme as useNavigationTheme } from 'expo-router';
import { SymbolView } from 'expo-symbols';
import { Fragment } from 'react';
import { Pressable, ScrollView, StyleSheet, Text, View } from 'react-native';

import { APP_LANGUAGES, LANGUAGE_LABELS } from '@/domain/types';
import { useStrings } from '@/i18n/useStrings';
import { useLauncherStore } from '@/store/LauncherStore';

const SECTION_INSET = 20;
const ROW_PADDING = 16;

/**
 * The app's one language setting, reached from the hub and from nowhere else.
 *
 * It used to live inside Phrases, where it only chose a catalog of lines, and
 * grew a second entry point on Weather once the widget started rendering
 * weekday names with it, in another process, in Swift. Now that the value picks
 * the entire interface it is self-evidently global, so the two pointer rows are
 * gone and the hub row is the only way in.
 */
export default function LanguageScreen() {
  const store = useLauncherStore();
  const { theme, language } = store.config;
  const router = useRouter();
  const { colors } = useNavigationTheme();
  const s = useStrings();

  const secondaryLabel = theme.isDark ? 'rgba(235, 235, 245, 0.6)' : 'rgba(60, 60, 67, 0.6)';

  return (
    <>
      <Stack.Screen options={{ title: s.sectionLanguage }} />
      <ScrollView
        contentInsetAdjustmentBehavior="automatic"
        style={{ backgroundColor: colors.background }}
        contentContainerStyle={styles.content}
      >
        <View style={[styles.card, { backgroundColor: colors.card }]}>
          {APP_LANGUAGES.map((choice, index) => (
            <Fragment key={choice}>
              {index > 0 && <View style={[styles.separator, { backgroundColor: colors.border }]} />}
              <Pressable
                accessibilityRole="button"
                accessibilityState={{ selected: choice === language }}
                style={styles.row}
                onPress={() => {
                  store.setLanguage(choice);
                  router.back();
                }}
              >
                {/*
                 * Each option is named in its own language and is never
                 * translated. It is what lets someone whose phone is in a
                 * language this app does not have, and who therefore landed on
                 * the English interface, find their own row without reading any
                 * English.
                 */}
                <Text style={[styles.rowLabel, { color: colors.text }]}>
                  {LANGUAGE_LABELS[choice]}
                </Text>
                {choice === language && (
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

        {/*
         * The second sentence is the reason this footer exists. Picking a row
         * rewrites `quotes.items`, which is the only thing in this app that
         * touches text the user wrote, so the warning has to sit next to the
         * rows that do it rather than on the Phrases screen it affects.
         */}
        <Text style={[styles.footer, { color: secondaryLabel }]}>{s.languageFooter}</Text>
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
  footer: {
    fontSize: 13,
    paddingHorizontal: SECTION_INSET + ROW_PADDING,
    paddingTop: 8,
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
