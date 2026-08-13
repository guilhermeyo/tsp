import { Stack, useTheme as useNavigationTheme } from 'expo-router';
import { SymbolView } from 'expo-symbols';
import { Fragment, useState } from 'react';
import {
  Pressable,
  ScrollView,
  StyleSheet,
  Text,
  TextInput,
  View,
} from 'react-native';

import { QUOTE_LANGUAGES, QUOTE_LANGUAGE_LABEL } from '@/domain/quotes';
import { useLauncherStore } from '@/store/LauncherStore';
import { fontFamilyFor } from '@/theme/fonts';

const SECTION_INSET = 20;
const ROW_PADDING = 16;

/**
 * The phrase list: pick a language, add your own, delete what you do not want.
 *
 * Switching language REPLACES the bundled set and keeps anything the user
 * wrote, which the store handles. That asymmetry is deliberate: the bundled
 * lines are content in one language and meaningless in the other, while a line
 * the user typed is theirs regardless.
 */
export default function QuotesScreen() {
  const store = useLauncherStore();
  const { quotes, theme } = store.config;
  const { colors } = useNavigationTheme();
  const [draft, setDraft] = useState('');

  const secondaryLabel = theme.isDark ? '#EBEBF599' : '#3C3C4399';
  const trimmed = draft.trim();
  const canAdd = trimmed !== '' && !quotes.items.includes(trimmed);

  function add(): void {
    if (!canAdd) return;
    store.addQuote(trimmed);
    setDraft('');
  }

  return (
    <>
      <Stack.Screen options={{ title: 'Phrases' }} />
      <ScrollView
        contentInsetAdjustmentBehavior="automatic"
        style={{ backgroundColor: colors.background }}
        contentContainerStyle={styles.content}
        keyboardShouldPersistTaps="handled"
        automaticallyAdjustKeyboardInsets
      >
        <Text style={[styles.sectionHeader, { color: secondaryLabel }]}>Language</Text>

        <View style={[styles.card, { backgroundColor: colors.card }]}>
          {QUOTE_LANGUAGES.map((language, index) => (
            <Fragment key={language}>
              {index > 0 && (
                <View style={[styles.separator, { backgroundColor: colors.border }]} />
              )}
              <Pressable
                accessibilityRole="button"
                accessibilityState={{ selected: language === quotes.language }}
                style={styles.row}
                onPress={() => store.setQuoteLanguage(language)}
              >
                <Text style={[styles.rowLabel, { color: colors.text }]}>
                  {QUOTE_LANGUAGE_LABEL[language]}
                </Text>
                {language === quotes.language && (
                  <SymbolView name="checkmark" size={15} weight="semibold" tintColor={colors.primary} />
                )}
              </Pressable>
            </Fragment>
          ))}
        </View>

        <Text style={[styles.sectionHeader, { color: secondaryLabel }]}>Add your own</Text>

        <View style={[styles.card, { backgroundColor: colors.card }]}>
          <View style={styles.row}>
            <TextInput
              value={draft}
              onChangeText={setDraft}
              placeholder="Keep it short"
              placeholderTextColor={secondaryLabel}
              style={[styles.input, { color: colors.text }]}
              keyboardAppearance={theme.isDark ? 'dark' : 'light'}
              returnKeyType="done"
              onSubmitEditing={add}
            />
            <Pressable onPress={add} disabled={!canAdd} hitSlop={8}>
              <Text
                style={[styles.action, { color: canAdd ? colors.primary : secondaryLabel }]}
              >
                Add
              </Text>
            </Pressable>
          </View>
        </View>

        <Text style={[styles.sectionHeader, { color: secondaryLabel }]}>
          {`${quotes.items.length} in rotation`}
        </Text>

        <View style={[styles.card, { backgroundColor: colors.card }]}>
          {quotes.items.map((item, index) => (
            <Fragment key={`${item}-${index}`}>
              {index > 0 && (
                <View style={[styles.separator, { backgroundColor: colors.border }]} />
              )}
              <View style={styles.row}>
                <Text
                  style={[
                    styles.quote,
                    { color: colors.text, fontFamily: fontFamilyFor(theme.font) },
                  ]}
                >
                  {item}
                </Text>
                <Pressable
                  onPress={() => store.removeQuoteAt(index)}
                  hitSlop={8}
                  accessibilityLabel={`Remove ${item}`}
                >
                  <SymbolView name="minus.circle.fill" size={20} tintColor="#FF453A" />
                </Pressable>
              </View>
            </Fragment>
          ))}
        </View>
      </ScrollView>
    </>
  );
}

const styles = StyleSheet.create({
  content: {
    paddingBottom: 48,
  },
  sectionHeader: {
    fontSize: 13,
    paddingHorizontal: SECTION_INSET + ROW_PADDING,
    paddingTop: 24,
    paddingBottom: 8,
  },
  card: {
    marginHorizontal: SECTION_INSET,
    borderRadius: 10,
    overflow: 'hidden',
  },
  row: {
    minHeight: 44,
    paddingHorizontal: ROW_PADDING,
    paddingVertical: 10,
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    gap: 12,
  },
  rowLabel: {
    fontSize: 17,
  },
  quote: {
    fontSize: 15,
    flexShrink: 1,
  },
  input: {
    flex: 1,
    fontSize: 17,
  },
  action: {
    fontSize: 17,
    fontWeight: '600',
  },
  separator: {
    height: StyleSheet.hairlineWidth,
    marginLeft: ROW_PADDING,
  },
});
