import { Stack, useRouter, useTheme as useNavigationTheme } from 'expo-router';
import { SymbolView } from 'expo-symbols';
import { Fragment, useState } from 'react';
import {
  Pressable,
  ScrollView,
  StyleSheet,
  Switch,
  Text,
  TextInput,
  View,
} from 'react-native';

import { DisclosureRow, ROW_PADDING, SECTION_INSET } from '@/components/DisclosureRow';
import {
  QUOTE_DURATIONS,
  QUOTE_DURATION_LABEL,
  QUOTE_DURATION_MS,
} from '@/domain/quotes';
import { LANGUAGE_LABELS } from '@/domain/types';
import { useLauncherStore } from '@/store/LauncherStore';
import { fontFamilyFor } from '@/theme/fonts';

/**
 * The phrase feature, whole: turn it on, choose its language, set how long it
 * stays, add your own, delete what you do not want.
 *
 * The on/off switch used to live in Appearance and the language used to be a
 * list of its own right here. Both moved for the same reason: the root is a hub
 * now, so a feature owns its own screen, and language stopped being a property
 * of the phrase catalog the moment the weather widget started rendering weekday
 * names with it. The row below only points at the one place that setting lives.
 *
 * Switching language REPLACES the bundled set and keeps anything the user
 * wrote, which the store handles. That asymmetry is deliberate: the bundled
 * lines are content in one language and meaningless in the other, while a line
 * the user typed is theirs regardless.
 */
export default function PhrasesScreen() {
  const store = useLauncherStore();
  const { quotes, theme, language } = store.config;
  const router = useRouter();
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
        <View style={[styles.firstCard, styles.card, { backgroundColor: colors.card }]}>
          {/*
            Off means the relay opens the target app immediately, with no cover
            phrase. Everything below stays live and editable while it is off:
            turning the feature back on should find the list where it was left.
          */}
          <View style={styles.row}>
            <Text style={[styles.rowLabel, { color: colors.text }]}>Show a phrase</Text>
            <Switch
              value={quotes.enabled}
              onValueChange={(value) => store.setQuotesEnabled(value)}
            />
          </View>

          <View style={[styles.separator, { backgroundColor: colors.border }]} />

          {/*
            A pointer, not a picker. The value shown is `config.language`, the
            authoritative copy; `quotes.language` mirrors it and is written by
            the same reducer case, so there is nothing here that could disagree.
          */}
          <DisclosureRow
            label="Language"
            value={LANGUAGE_LABELS[language]}
            onPress={() => router.push('/language')}
          />
        </View>

        <Text style={[styles.sectionHeader, { color: secondaryLabel }]}>How long it stays</Text>

        <View style={[styles.card, { backgroundColor: colors.card }]}>
          {QUOTE_DURATIONS.map((duration, index) => (
            <Fragment key={duration}>
              {index > 0 && (
                <View style={[styles.separator, { backgroundColor: colors.border }]} />
              )}
              <Pressable
                accessibilityRole="button"
                accessibilityState={{ selected: duration === quotes.duration }}
                style={styles.row}
                onPress={() => store.setQuoteDuration(duration)}
              >
                <Text style={[styles.rowLabel, { color: colors.text }]}>
                  {QUOTE_DURATION_LABEL[duration]}
                </Text>
                <View style={styles.disclosure}>
                  <Text style={[styles.value, { color: secondaryLabel }]}>
                    {`${(QUOTE_DURATION_MS[duration] / 1000).toFixed(1)}s`}
                  </Text>
                  {duration === quotes.duration && (
                    <SymbolView name="checkmark" size={15} weight="semibold" tintColor={colors.primary} />
                  )}
                </View>
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
  // Every other card on this screen is spaced by the section header above it.
  // The first one has none, so it carries the same gap itself.
  firstCard: {
    marginTop: 24,
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
  disclosure: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 8,
  },
  value: {
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
