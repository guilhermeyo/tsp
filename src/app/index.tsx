import Constants from 'expo-constants';
import { useRouter, useTheme as useNavigationTheme } from 'expo-router';
import { ScrollView, StyleSheet, Text, View } from 'react-native';

import { DisclosureRow, ROW_PADDING, SECTION_INSET } from '@/components/DisclosureRow';
import { FONT_LABELS, LANGUAGE_LABELS, SIZE_LABELS } from '@/domain/types';
import { useLauncherStore } from '@/store/LauncherStore';

/**
 * THE HUB. Every section of the app is one tap from here.
 *
 * This used to be the app list, with everything else hidden behind a gear in
 * the corner. That shape came from the SwiftUI original, where the launcher WAS
 * the list and appearance was its only setting. It stopped being true the
 * moment there were four sections, and a single icon in a corner is the wrong
 * rank for any of them -- Weather in particular is a second widget, not a
 * preference of the first.
 *
 * The rule this screen follows, and the reason (modals) still exists: a section
 * is a PLACE, so it pushes and keeps a back chevron; a sheet is a TASK with
 * cancel-or-confirm semantics, which is only the app form and the catalog.
 *
 * There is no plus button here. Adding what, from a screen that lists five
 * different things? The Apps row is the affordance instead, and it lands on the
 * list with its own plus: adding an app from a cold launch is two taps.
 *
 * NOTHING BUT ROWS. Both widget previews used to sit at the top of this screen
 * and both have moved next to the thing they preview -- the launcher card to
 * /apps, the forecast to /weather. They were also what made this screen scroll,
 * and a screen that scrolls under a translucent large title puts a hard-edged
 * black card behind the blur, which is what the previews looked broken doing.
 * Two grouped cards and a footer fit without scrolling at every text size, so
 * the title never collapses and nothing can pass under the bar. Do not put a
 * preview back here.
 */
export default function HubScreen() {
  const store = useLauncherStore();
  const router = useRouter();
  const { colors } = useNavigationTheme();

  const { apps, theme, quotes, weather, language } = store.config;

  const secondaryLabel = theme.isDark ? 'rgba(235, 235, 245, 0.6)' : 'rgba(60, 60, 67, 0.6)';

  // Off is a real state for both of these and reads better than a zero: the
  // user did not run out of phrases, they turned phrases off.
  const weatherValue = !weather.enabled
    ? 'Off'
    : weather.placeName === ''
      ? 'No city'
      : weather.placeName;
  const phrasesValue = quotes.enabled ? `${quotes.items.length}` : 'Off';

  const version = Constants.expoConfig?.version ?? '';

  return (
    <ScrollView
      // Required for the large title to collapse into the bar on scroll -- the
      // native header measures the scroll view's adjusted inset. The app list
      // is the one screen that cannot use this; see the long note in apps.tsx.
      contentInsetAdjustmentBehavior="automatic"
      style={{ backgroundColor: colors.background }}
      contentContainerStyle={styles.content}
    >
      {/* The features. Each one is something the widget or the relay renders. */}
      <View style={[styles.card, { backgroundColor: colors.card }]}>
        <DisclosureRow label="Apps" value={`${apps.length}`} onPress={() => router.push('/apps')} />
        <View style={[styles.separator, { backgroundColor: colors.border }]} />
        <DisclosureRow
          label="Weather"
          value={weatherValue}
          onPress={() => router.push('/weather')}
        />
        <View style={[styles.separator, { backgroundColor: colors.border }]} />
        <DisclosureRow
          label="Phrases"
          value={phrasesValue}
          onPress={() => router.push('/phrases')}
        />
      </View>

      {/*
        A second card, not three more rows in the first one. These two are not
        features: they are settings that cut ACROSS every feature above. Font
        and size drive the launcher rows and the preview; language drives both
        the phrase catalog here and the weekday abbreviations the weather widget
        renders in another process.
      */}
      <View style={[styles.card, { backgroundColor: colors.card }]}>
        <DisclosureRow
          label="Appearance"
          value={`${FONT_LABELS[theme.font]}, ${SIZE_LABELS[theme.size]}`}
          onPress={() => router.push('/appearance')}
        />
        <View style={[styles.separator, { backgroundColor: colors.border }]} />
        <DisclosureRow
          label="Language"
          value={LANGUAGE_LABELS[language]}
          onPress={() => router.push('/language')}
        />
      </View>

      {/*
        The Open-Meteo line is not decoration. Their free tier is CC BY 4.0,
        which requires attribution, and the widget itself has no room for it --
        five columns of forecast fill a systemMedium completely. This is where
        the app pays for the data.
      */}
      <View style={styles.footer}>
        <Text style={[styles.footerText, { color: secondaryLabel }]}>
          {version === '' ? 'The Simple Phone' : `The Simple Phone ${version}`}
        </Text>
        <Text style={[styles.footerText, { color: secondaryLabel }]}>
          Weather data by Open-Meteo.com, CC BY 4.0
        </Text>
      </View>
    </ScrollView>
  );
}

const styles = StyleSheet.create({
  content: {
    paddingBottom: 32,
  },
  card: {
    marginTop: 24,
    marginHorizontal: SECTION_INSET,
    borderRadius: 10,
    overflow: 'hidden',
  },
  separator: {
    height: StyleSheet.hairlineWidth,
    marginLeft: ROW_PADDING,
  },
  footer: {
    alignItems: 'center',
    gap: 4,
    paddingHorizontal: SECTION_INSET + ROW_PADDING,
    paddingTop: 32,
  },
  footerText: {
    fontSize: 13,
    textAlign: 'center',
  },
});
