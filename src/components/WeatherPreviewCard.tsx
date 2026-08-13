import { SymbolView } from 'expo-symbols';
import { useEffect, useState } from 'react';
import { StyleSheet, Text, View } from 'react-native';

import type { AppLanguage, Theme, Weather } from '@/domain/types';
import { useStrings } from '@/i18n/useStrings';
import { fontFamilyFor } from '@/theme/fonts';
import { textColor } from '@/theme/tokens';
import type { SymbolViewProps } from 'expo-symbols';

/**
 * What the weather widget will look like, rendered in the app.
 *
 * TWIN FILE. Change this and `ios/SimplePhoneWidget/WeatherWidgetView.swift`
 * together, the same way `LauncherRowLabel.tsx` twins its Swift counterpart.
 * The compiler cannot enforce their agreement, and the widget is the one that
 * ships to the home screen, so it is the reference and this follows it.
 *
 * It fetches its own forecast rather than reading the widget's cache. The cache
 * lives under `weather_cache`, a key the widget owns and the native module does
 * not expose, and threading a second reader through the bridge to save one
 * request on a screen the user opens by hand is not a trade worth making.
 */

/** Mirrors `WeatherCondition.init(wmoCode:)`. Anything unlisted is cloudy, which claims nothing. */
function symbolFor(code: number): SymbolViewProps['name'] {
  if (code === 0) return 'sun.max';
  if (code === 1 || code === 2) return 'cloud.sun';
  if (code === 45 || code === 48) return 'cloud.fog';
  if (code === 51 || code === 53 || code === 55) return 'cloud.drizzle';
  if (code === 56 || code === 57 || code === 66 || code === 67) return 'cloud.sleet';
  if (code === 61 || code === 63) return 'cloud.rain';
  if (code === 65 || code === 82) return 'cloud.heavyrain';
  if (code === 80 || code === 81) return 'cloud.sun.rain';
  if (code === 71 || code === 73 || code === 75 || code === 85 || code === 86) return 'cloud.snow';
  if (code === 77) return 'snowflake';
  if (code === 95) return 'cloud.bolt.rain';
  if (code === 96 || code === 99) return 'cloud.hail';
  return 'cloud';
}

interface Day {
  weekday: string;
  code: number;
  temperature: number;
}

type State =
  | { status: 'idle' }
  | { status: 'loading' }
  | { status: 'ok'; days: Day[] }
  | { status: 'failed' };

/**
 * Local noon, so a timezone shift cannot roll the label onto the wrong day.
 *
 * `language` is the stored app tag, which now includes 'es' and 'ja'. Nothing
 * here ships weekday data: Hermes delegates `Intl` to the platform ICU on iOS,
 * so these abbreviations come from Foundation, the same source the widget's
 * SwiftUI twin reads through `Locale(identifier:)`. That is also why this is the
 * one line on this screen whose output cannot be verified by reading the code.
 */
function weekdayLabel(isoDate: string, language: AppLanguage): string {
  const date = new Date(`${isoDate}T12:00:00`);
  // Lowercased with the SAME language that produced it, mirroring the Swift
  // twin's `lowercased(with: formatter.locale)`. A bare `toLowerCase()` is not
  // good enough for the same reason it is not good enough there: Turkish maps a
  // dotted I differently. Lowercase because that is TSP's voice, and because
  // this card is supposed to be indistinguishable from the widget beside it.
  return new Intl.DateTimeFormat(language, { weekday: 'short' })
    .format(date)
    .toLocaleLowerCase(language);
}

export function WeatherPreviewCard({
  weather,
  theme,
  language,
}: {
  weather: Weather;
  theme: Theme;
  language: AppLanguage;
}) {
  const [state, setState] = useState<State>({ status: 'idle' });
  const s = useStrings();
  const { latitude, longitude, unit } = weather;

  useEffect(() => {
    if (latitude === null || longitude === null) {
      setState({ status: 'idle' });
      return;
    }
    let cancelled = false;
    setState({ status: 'loading' });

    const url =
      'https://api.open-meteo.com/v1/forecast' +
      `?latitude=${latitude}&longitude=${longitude}` +
      '&daily=weather_code,temperature_2m_max' +
      `&timezone=auto&forecast_days=5&temperature_unit=${unit}`;

    fetch(url)
      .then((response) => (response.ok ? response.json() : Promise.reject(new Error('http'))))
      .then((json: { daily: { time: string[]; weather_code: number[]; temperature_2m_max: number[] } }) => {
        if (cancelled) return;
        const d = json.daily;
        setState({
          status: 'ok',
          days: d.time.map((iso, i) => ({
            weekday: weekdayLabel(iso, language),
            code: d.weather_code[i] ?? 3,
            temperature: Math.round(d.temperature_2m_max[i] ?? 0),
          })),
        });
      })
      .catch(() => {
        if (!cancelled) setState({ status: 'failed' });
      });

    return () => {
      cancelled = true;
    };
  }, [latitude, longitude, unit, language]);

  const color = textColor(theme);
  const dim = theme.isDark ? 'rgba(235, 235, 245, 0.6)' : 'rgba(60, 60, 67, 0.6)';
  const family = fontFamilyFor(theme.font);

  return (
    <View
      style={[
        styles.card,
        {
          backgroundColor: theme.isDark ? '#000000' : '#FFFFFF',
          // The same hairline WidgetPreviewCard draws, for the same reason: the
          // fill is the widget's own background, which in dark mode is #000000
          // on a page that is rgb(1, 1, 1). Without an edge there is no card,
          // just text floating on the screen. Copied from WidgetPreviewCard
          // rather than re-picked, so the two widget mocks match by
          // construction.
          borderColor: theme.isDark ? 'rgba(255, 255, 255, 0.12)' : 'rgba(0, 0, 0, 0.12)',
        },
      ]}
    >
      {state.status === 'ok' ? (
        <View style={styles.row}>
          {state.days.map((day, index) => (
            <View key={`${day.weekday}-${index}`} style={styles.column}>
              <Text style={[styles.weekday, { color: dim, fontFamily: family }]}>{day.weekday}</Text>
              <SymbolView name={symbolFor(day.code)} size={26} tintColor={color} weight="light" />
              <Text style={[styles.temperature, { color, fontFamily: family }]}>
                {`${day.temperature}°`}
              </Text>
            </View>
          ))}
        </View>
      ) : (
        <Text style={[styles.message, { color: dim, fontFamily: family }]}>
          {state.status === 'failed'
            ? s.weatherPreviewFailed
            : state.status === 'loading'
              ? s.commonLoading
              : s.weatherPreviewIdle}
        </Text>
      )}
    </View>
  );
}

const styles = StyleSheet.create({
  card: {
    // 24 and a 1pt border, matching WidgetPreviewCard. The two mocks sit two
    // taps apart and any difference between them reads as one of them being
    // wrong.
    borderRadius: 24,
    borderWidth: 1,
    overflow: 'hidden',
    paddingHorizontal: 8,
    paddingVertical: 14,
    minHeight: 108,
    justifyContent: 'center',
  },
  row: {
    flexDirection: 'row',
    alignItems: 'flex-start',
  },
  column: {
    flex: 1,
    alignItems: 'center',
    gap: 7,
  },
  weekday: {
    fontSize: 13,
    fontWeight: '600',
  },
  temperature: {
    fontSize: 17,
    fontWeight: '600',
  },
  message: {
    fontSize: 14,
    textAlign: 'center',
    paddingHorizontal: 16,
  },
});
