import { Stack, useTheme as useNavigationTheme } from 'expo-router';
import { SymbolView } from 'expo-symbols';
import { Fragment, useEffect, useMemo, useState } from 'react';
import {
  AppState,
  Pressable,
  ScrollView,
  StyleSheet,
  Switch,
  Text,
  TextInput,
  View,
} from 'react-native';

import { ROW_PADDING, SECTION_INSET } from '@/components/DisclosureRow';
import { QUOTE_DURATIONS, QUOTE_DURATION_MS } from '@/domain/quotes';
import { countNeverShown, parseQuoteCounts, readQuoteStatsJSON } from '@/domain/quoteStats';
import { useStrings } from '@/i18n/useStrings';
import { useLauncherStore } from '@/store/LauncherStore';
import { fontFamilyFor } from '@/theme/fonts';

/**
 * The phrase feature, whole: turn it on, set how long it stays, add your own,
 * delete what you do not want.
 *
 * The on/off switch used to live in Appearance and there used to be a Language
 * row here as well. Both moved for the same reason: the root is a hub now, so a
 * feature owns its own screen. Language went further and left entirely — it
 * stopped being a property of the phrase catalog the moment the weather widget
 * started rendering weekday names with it, and now that it also picks the
 * interface strings it is plainly global. The hub row is its only surface.
 *
 * Switching language REPLACES the bundled set and keeps anything the user
 * wrote, which the store handles. That asymmetry is deliberate: the bundled
 * lines are content in one language and meaningless in the other, while a line
 * the user typed is theirs regardless.
 */
export default function PhrasesScreen() {
  const store = useLauncherStore();
  const { quotes, theme } = store.config;
  const s = useStrings();
  const { colors } = useNavigationTheme();
  const [draft, setDraft] = useState('');
  /** Optional. Blank means the line has no attribution, which is most of them. */
  const [author, setAuthor] = useState('');
  /** null while adding, an index while editing an existing line in place. */
  const [editingText, setEditingText] = useState<string | null>(null);

  // Seeded synchronously, the same trick the store uses with useReducer: the
  // native read is a JSI Function, so the first render already has the real
  // numbers. No loading flag, no flash of blanks.
  const [rawStats, setRawStats] = useState(readQuoteStatsJSON);
  const counts = useMemo(() => parseQuoteCounts(rawStats), [rawStats]);

  useEffect(() => {
    // A count can only change while the app is in the BACKGROUND, because that
    // is the one place a phrase is drawn. So there is nothing to poll and
    // nothing to subscribe to, and re-reading on every return covers the only
    // stale case there is: this screen open, app switcher, back to this screen.
    const subscription = AppState.addEventListener('change', (state) => {
      if (state === 'active') setRawStats(readQuoteStatsJSON());
    });
    return () => subscription.remove();
  }, []);

  const secondaryLabel = theme.isDark ? '#EBEBF599' : '#3C3C4399';
  const neverShown = countNeverShown(quotes.items, counts);
  const trimmed = draft.trim();
  const trimmedAuthor = author.trim();
  // Editing keeps its own row out of the duplicate check: re-saving a line
  // without changing its text must not be refused as a duplicate of itself.
  const collides = quotes.items.some(
    (item) => item.text !== editingText && item.text === trimmed
  );
  const canAdd = trimmed !== '' && !collides;

  function add(): void {
    if (!canAdd) return;
    if (editingText === null) {
      store.addQuote(trimmed, trimmedAuthor);
    } else {
      store.updateQuote(editingText, trimmed, trimmedAuthor);
    }
    setEditingText(null);
    setAuthor('');
    setDraft('');
  }

  return (
    <>
      <Stack.Screen options={{ title: s.sectionPhrases }} />
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
            <Text style={[styles.rowLabel, { color: colors.text }]}>{s.phrasesEnable}</Text>
            <Switch
              value={quotes.enabled}
              onValueChange={(value) => store.setQuotesEnabled(value)}
            />
          </View>
        </View>

        <Text style={[styles.sectionHeader, { color: secondaryLabel }]}>
          {s.phrasesSectionDuration}
        </Text>

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
                  {s.quoteDurationLabels[duration]}
                </Text>
                <View style={styles.disclosure}>
                  <Text style={[styles.value, { color: secondaryLabel }]}>
                    {s.phrasesDurationSeconds(QUOTE_DURATION_MS[duration] / 1000)}
                  </Text>
                  {duration === quotes.duration && (
                    <SymbolView name="checkmark" size={15} weight="semibold" tintColor={colors.primary} />
                  )}
                </View>
              </Pressable>
            </Fragment>
          ))}
        </View>

        <Text style={[styles.sectionHeader, { color: secondaryLabel }]}>
          {s.phrasesSectionAdd}
        </Text>

        <View style={[styles.card, { backgroundColor: colors.card }]}>
          <View style={styles.row}>
            <TextInput
              value={draft}
              onChangeText={setDraft}
              placeholder={s.phrasesAddHint}
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
                {editingText === null ? s.commonAdd : s.commonSave}
              </Text>
            </Pressable>
          </View>

          <View style={[styles.separator, { backgroundColor: colors.border }]} />

          {/*
            Optional, and it looks optional: its own row, its own placeholder,
            and nothing about the confirm button depends on it. Most lines in
            this app are original and unattributed.
          */}
          <View style={styles.row}>
            <TextInput
              value={author}
              onChangeText={setAuthor}
              placeholder={s.phrasesAuthorHint}
              placeholderTextColor={secondaryLabel}
              style={[styles.input, { color: colors.text }]}
              keyboardAppearance={theme.isDark ? 'dark' : 'light'}
              returnKeyType="done"
              onSubmitEditing={add}
            />
            {editingText !== null && (
              <Pressable
                onPress={() => {
                  setEditingText(null);
                  setDraft('');
                  setAuthor('');
                }}
                hitSlop={8}
              >
                <Text style={[styles.action, { color: secondaryLabel }]}>{s.commonCancel}</Text>
              </Pressable>
            )}
          </View>
        </View>

        {/*
          The count beside each line is how many times it has been put up as a
          cover. "Not yet shown" is the spread statistic, and it is the one the
          native draw minimises: it walks down to zero over a cycle, at which
          point this header reads exactly as it did before any of this existed.
        */}
        <Text style={[styles.sectionHeader, { color: secondaryLabel }]}>
          {neverShown === 0
            ? s.phrasesRotation(quotes.items.length)
            : s.phrasesRotationUnshown(quotes.items.length, neverShown)}
        </Text>

        <View style={[styles.card, { backgroundColor: colors.card }]}>
          {quotes.items.map((item, index) => {
            // Read into a local rather than indexing three times: `counts` is
            // keyed by an arbitrary string, which TypeScript will not narrow
            // through an element access, and `a11yShownTimes` takes a number.
            const count = counts[item.text];

            return (
              <Fragment key={`${item}-${index}`}>
                {index > 0 && (
                  <View style={[styles.separator, { backgroundColor: colors.border }]} />
                )}
                <View style={styles.row}>
                  {/*
                    Tapping loads the line into the form above instead of
                    opening a sheet: the form is already on this screen, and a
                    modal for two fields would be more chrome than content.
                  */}
                  <Pressable
                    style={styles.quoteBlock}
                    onPress={() => {
                      setEditingText(item.text);
                      setDraft(item.text);
                      setAuthor(item.author ?? '');
                    }}
                  >
                    <Text
                      style={[
                        styles.quote,
                        { color: colors.text, fontFamily: fontFamilyFor(theme.font) },
                      ]}
                    >
                      {item.text}
                    </Text>
                    {item.author !== undefined && (
                      <Text
                        style={[
                          styles.author,
                          { color: secondaryLabel, fontFamily: fontFamilyFor(theme.font) },
                        ]}
                      >
                        {item.author}
                      </Text>
                    )}
                  </Pressable>
                  {/*
                    Fixed width and right aligned so the minus buttons stay in one
                    straight line down the card whatever the numbers are, with
                    tabular figures so the digits do not jitter as a count crosses
                    into three. Zero renders blank but still holds the slot, so
                    nothing shifts the first time a number lands.
                  */}
                  <Text
                    style={[styles.count, { color: secondaryLabel }]}
                    accessibilityLabel={
                      count === undefined ? s.a11yNotYetShown : s.a11yShownTimes(count)
                    }
                  >
                    {count === undefined ? '' : String(count)}
                  </Text>
                  <Pressable
                    onPress={() => {
                      // Leaving edit mode pointed at a line that no longer
                      // exists would strand the form: the save would find no
                      // anchor and silently do nothing.
                      if (editingText === item.text) {
                        setEditingText(null);
                        setDraft('');
                        setAuthor('');
                      }
                      store.removeQuoteAt(index);
                    }}
                    hitSlop={8}
                    accessibilityLabel={s.a11yRemovePhrase(item.text)}
                  >
                    <SymbolView name="minus.circle.fill" size={20} tintColor="#FF453A" />
                  </Pressable>
                </View>
              </Fragment>
            );
          })}
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
  quoteBlock: {
    flexShrink: 1,
    gap: 2,
  },
  author: {
    fontSize: 12,
  },
  quote: {
    fontSize: 15,
    flexShrink: 1,
  },
  count: {
    fontSize: 15,
    minWidth: 32,
    textAlign: 'right',
    fontVariant: ['tabular-nums'],
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
