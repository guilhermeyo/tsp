import { Stack, useTheme as useNavigationTheme } from 'expo-router';
import { SymbolView } from 'expo-symbols';
import { Fragment, useEffect, useRef, useState } from 'react';
import {
  ActivityIndicator,
  Keyboard,
  Pressable,
  ScrollView,
  StyleSheet,
  Switch,
  Text,
  TextInput,
  View,
} from 'react-native';

import { SegmentedControl } from '@/components/SegmentedControl';
import { WeatherPreviewCard } from '@/components/WeatherPreviewCard';
import { guessPlaceFromNetwork, searchPlaces, type GeocodingPlace } from '@/domain/geocoding';
import { TEMPERATURE_UNITS, type TemperatureUnit } from '@/domain/types';
import { useStrings } from '@/i18n/useStrings';
import { useLauncherStore } from '@/store/LauncherStore';

const SECTION_INSET = 20;
const ROW_PADDING = 16;

/**
 * Long enough that typing "Sao Paulo" is one request rather than nine, short
 * enough that the list appears while the finger is still on the keyboard.
 */
const DEBOUNCE_MS = 350;

/**
 * Two decimals is about a kilometre, which is finer than any weather model's
 * grid and is exactly what the widget asks the forecast endpoint for. Storing
 * the endpoint's full precision would only make the same request under a
 * longer name.
 */
function roundCoordinate(value: number): number {
  return Math.round(value * 100) / 100;
}

/**
 * `failed` is a separate state from an empty `places` on purpose. "No city
 * matched" and "the search never answered" look identical if you only count
 * rows, and telling a user their city does not exist because their Wi-Fi is
 * down is the kind of quiet lie this app has already cost hours to.
 */
type SearchState =
  | { status: 'idle' }
  | { status: 'searching' }
  | { status: 'done'; places: GeocodingPlace[] }
  | { status: 'failed' };

/**
 * Where the weather widget gets its city and its unit. Its weekday names follow
 * the language, which is set on the hub and no longer has a row here.
 *
 * Also the destination of the widget's own tap: `simplephonern://weather` is a
 * new HOST on the existing scheme, so `Relay.target(from:)` in AppDelegate
 * declines it and Expo Router routes it here.
 */
export default function WeatherScreen() {
  const store = useLauncherStore();
  const { theme, weather, language } = store.config;
  const s = useStrings();
  const { colors } = useNavigationTheme();

  const secondaryLabel = theme.isDark ? 'rgba(235, 235, 245, 0.6)' : 'rgba(60, 60, 67, 0.6)';
  const tertiaryLabel = theme.isDark ? 'rgba(235, 235, 245, 0.3)' : 'rgba(60, 60, 67, 0.3)';

  const [query, setQuery] = useState('');
  /** Guards the one-shot seed below against Fast Refresh and remounts. */
  const seeded = useRef(false);
  const [search, setSearch] = useState<SearchState>({ status: 'idle' });

  /**
   * Which request the screen is currently showing. Every keystroke claims a new
   * number, and a response whose number is stale is dropped: without it, a slow
   * answer for "Sa" can land after a fast one for "Sao Paulo" and replace it.
   */
  const requestId = useRef(0);

  useEffect(() => {
    const trimmed = query.trim();
    if (trimmed === '') {
      // Also invalidates anything in flight, so clearing the field cannot be
      // undone a second later by a response that was already on its way.
      requestId.current += 1;
      setSearch({ status: 'idle' });
      return;
    }

    const id = (requestId.current += 1);
    setSearch({ status: 'searching' });

    const timer = setTimeout(() => {
      void searchPlaces(trimmed, language).then((outcome) => {
        if (requestId.current !== id) return;
        setSearch(
          outcome.status === 'failed'
            ? { status: 'failed' }
            : { status: 'done', places: outcome.places }
        );
      });
    }, DEBOUNCE_MS);

    return () => clearTimeout(timer);
  }, [query, language]);

  /**
   * Seed a city the first time this screen is opened with none set.
   *
   * An IP lookup, deliberately, not CoreLocation: it lands within tens of
   * kilometres, which is the right accuracy for a five-day forecast, and it
   * costs no permission prompt in an app whose pitch is that it asks for
   * nothing. Silent on failure, because the fallback is the search field that
   * is already on screen.
   */
  useEffect(() => {
    if (seeded.current || weather.placeName !== '') return;
    seeded.current = true;
    let cancelled = false;
    guessPlaceFromNetwork().then((place) => {
      if (cancelled || place === null) return;
      store.setWeatherPlace({
        latitude: roundCoordinate(place.latitude),
        longitude: roundCoordinate(place.longitude),
        placeName: place.name,
      });
    });
    return () => {
      cancelled = true;
    };
  }, [weather.placeName, store]);

  function choose(place: GeocodingPlace): void {
    store.setWeatherPlace({
      latitude: roundCoordinate(place.latitude),
      longitude: roundCoordinate(place.longitude),
      placeName: place.name,
    });
    // Emptying the field runs the effect above, which clears the result list
    // and invalidates the in-flight request.
    setQuery('');
    Keyboard.dismiss();
  }

  function selectUnit(unit: TemperatureUnit): void {
    store.setTemperatureUnit(unit);
  }

  return (
    <>
      <Stack.Screen options={{ title: s.sectionWeather }} />
      <ScrollView
        contentInsetAdjustmentBehavior="automatic"
        style={{ backgroundColor: colors.background }}
        contentContainerStyle={styles.content}
        keyboardShouldPersistTaps="handled"
        automaticallyAdjustKeyboardInsets
      >
        {/*
          The preview sits ABOVE the controls, so choosing a city or flipping
          the unit shows its result in place instead of sending the user to the
          home screen to find out.
        */}
        <View style={styles.previewRow}>
          <WeatherPreviewCard weather={weather} theme={theme} language={language} />
        </View>

        <View style={[styles.card, { backgroundColor: colors.card }]}>
          <View style={styles.row}>
            <Text style={[styles.rowLabel, { color: colors.text }]}>{s.weatherEnable}</Text>
            <Switch
              value={weather.enabled}
              onValueChange={(enabled) => store.setWeatherEnabled(enabled)}
            />
          </View>
        </View>

        <Text style={[styles.sectionHeader, { color: secondaryLabel }]}>{s.weatherSectionCity}</Text>

        <View style={[styles.card, { backgroundColor: colors.card }]}>
          <View style={styles.row}>
            <Text style={[styles.rowLabel, { color: colors.text }]}>{s.weatherForecastFor}</Text>
            <Text
              style={[
                styles.value,
                { color: weather.placeName === '' ? tertiaryLabel : secondaryLabel },
              ]}
              numberOfLines={1}
            >
              {weather.placeName === '' ? s.weatherNoCityYet : weather.placeName}
            </Text>
          </View>
        </View>

        <Text style={[styles.sectionHeader, { color: secondaryLabel }]}>
          {s.weatherSectionSearch}
        </Text>

        <View style={[styles.card, { backgroundColor: colors.card }]}>
          <View style={styles.row}>
            <TextInput
              value={query}
              onChangeText={setQuery}
              placeholder={s.weatherSearchHint}
              placeholderTextColor={secondaryLabel}
              style={[styles.input, { color: colors.text }]}
              keyboardAppearance={theme.isDark ? 'dark' : 'light'}
              autoCorrect={false}
              autoCapitalize="words"
              returnKeyType="search"
              clearButtonMode="while-editing"
            />
            {search.status === 'searching' && <ActivityIndicator color={secondaryLabel} />}
          </View>

          {search.status === 'done' &&
            search.places.map((place, index) => (
              <Fragment key={`${place.name}-${place.latitude}-${place.longitude}-${index}`}>
                <View style={[styles.separator, { backgroundColor: colors.border }]} />
                <Pressable accessibilityRole="button" style={styles.row} onPress={() => choose(place)}>
                  <View style={styles.result}>
                    <Text style={[styles.rowLabel, { color: colors.text }]} numberOfLines={1}>
                      {place.name}
                    </Text>
                    {place.subtitle !== '' && (
                      <Text style={[styles.subtitle, { color: secondaryLabel }]} numberOfLines={1}>
                        {place.subtitle}
                      </Text>
                    )}
                  </View>
                  <SymbolView
                    name="chevron.right"
                    size={14}
                    weight="semibold"
                    tintColor={tertiaryLabel}
                    style={styles.chevron}
                  />
                </Pressable>
              </Fragment>
            ))}

          {/*
            Both of these are said out loud rather than left as an empty list.
            An empty list means "your city does not exist", which is a lie when
            the request never left the phone.
          */}
          {search.status === 'done' && search.places.length === 0 && (
            <>
              <View style={[styles.separator, { backgroundColor: colors.border }]} />
              <View style={styles.row}>
                <Text style={[styles.message, { color: secondaryLabel }]}>
                  {s.weatherSearchNoMatch(query.trim())}
                </Text>
              </View>
            </>
          )}

          {search.status === 'failed' && (
            <>
              <View style={[styles.separator, { backgroundColor: colors.border }]} />
              <View style={styles.row}>
                <Text style={[styles.message, { color: colors.notification }]}>
                  {s.weatherSearchFailed}
                </Text>
              </View>
            </>
          )}
        </View>

        <Text style={[styles.footer, { color: secondaryLabel }]}>{s.weatherFooterPrivacy}</Text>

        <Text style={[styles.sectionHeader, { color: secondaryLabel }]}>
          {s.weatherSectionUnits}
        </Text>

        <View style={[styles.card, { backgroundColor: colors.card }]}>
          {/*
            Same shape as the Alignment row on Appearance: the control alone,
            full width, with the label kept for VoiceOver only.
          */}
          <View style={styles.segmentRow}>
            <SegmentedControl
              accessibilityLabel={s.a11yTemperatureUnit}
              options={TEMPERATURE_UNITS}
              labels={s.temperatureUnitLabels}
              value={weather.unit}
              onChange={selectUnit}
              isDark={theme.isDark}
            />
          </View>
        </View>

        {/*
          This screen used to end with a Language section pointing at
          /language, plus a footer promising the widget's weekday names follow
          "this setting, not the phone's language". Both are gone: the setting
          now drives the entire interface, so it lives once, on the hub, and the
          footer's distinction stopped being interesting the moment the phone's
          language became the first-run default.
        */}
        <Text style={[styles.footer, { color: secondaryLabel }]}>{s.weatherFooterUnits}</Text>
      </ScrollView>
    </>
  );
}

const styles = StyleSheet.create({
  previewRow: {
    paddingHorizontal: SECTION_INSET + 12,
    paddingVertical: 12,
  },
  content: {
    paddingTop: 24,
    paddingBottom: 48,
  },
  sectionHeader: {
    fontSize: 13,
    // Rendered as written, like SwiftUI's Form. Do not uppercase.
    paddingHorizontal: SECTION_INSET + ROW_PADDING,
    paddingTop: 24,
    paddingBottom: 8,
  },
  footer: {
    fontSize: 13,
    paddingHorizontal: SECTION_INSET + ROW_PADDING,
    paddingTop: 8,
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
  segmentRow: {
    justifyContent: 'center',
    minHeight: 44,
    paddingHorizontal: ROW_PADDING,
    paddingVertical: 8,
  },
  result: {
    flexShrink: 1,
    gap: 2,
  },
  subtitle: {
    fontSize: 13,
  },
  message: {
    fontSize: 15,
    flexShrink: 1,
  },
  value: {
    fontSize: 17,
    flexShrink: 1,
  },
  input: {
    flex: 1,
    fontSize: 17,
  },
  chevron: {
    width: 10,
    height: 16,
  },
  separator: {
    height: StyleSheet.hairlineWidth,
    marginLeft: ROW_PADDING,
  },
});
