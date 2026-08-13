import { Stack, useRouter, useTheme as useNavigationTheme } from 'expo-router';
import { SymbolView } from 'expo-symbols';
import { Fragment } from 'react';
import { Pressable, ScrollView, StyleSheet, Text, View } from 'react-native';

import { APP_LANGUAGES, LANGUAGE_LABELS } from '@/domain/types';
import { useLauncherStore } from '@/store/LauncherStore';

const SECTION_INSET = 20;
const ROW_PADDING = 16;

/**
 * The app's one language setting, reachable from the hub, from Phrases and from
 * Weather, all pushing this same route.
 *
 * It used to live inside Phrases, where it only chose a catalog of lines. It
 * moved out when the weather widget started rendering weekday names with it, in
 * another process, in Swift: a user who only wants the widget should not have
 * to open a phrases screen to change how their forecast reads.
 */
export default function LanguageScreen() {
  const store = useLauncherStore();
  const { theme, language } = store.config;
  const router = useRouter();
  const { colors } = useNavigationTheme();

  const secondaryLabel = theme.isDark ? 'rgba(235, 235, 245, 0.6)' : 'rgba(60, 60, 67, 0.6)';

  return (
    <>
      <Stack.Screen options={{ title: 'Language' }} />
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
                {/* Each option is named in its own language, never translated. */}
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

        <Text style={[styles.footer, { color: secondaryLabel }]}>
          Sets the bundled phrases and the weekday names in the weather widget. Switching replaces
          the bundled phrases with the other language&apos;s and keeps every line you wrote
          yourself.
        </Text>
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
