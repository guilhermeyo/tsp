/**
 * City search, the one thing the weather widget cannot work out on its own.
 *
 * The widget fetches its forecast itself, in Swift, from Open-Meteo. It never
 * asks anyone where it is: there is no CoreLocation in the extension and no
 * location permission in the app. The coordinates come from here instead, typed
 * once by the user and stored in `weather` inside the shared config.
 *
 * Same provider as the forecast, so a city that geocodes here always has a
 * forecast there. No key, no account, no dependency: one GET over the global
 * `fetch`, which is why nothing had to be added to `ios/` for this file.
 */

import type { AppLanguage } from './types';

const ENDPOINT = 'https://geocoding-api.open-meteo.com/v1/search';

/** Five is what the screen shows, so five is what we ask for. */
const RESULT_COUNT = 5;

/**
 * A search that has not answered in eight seconds is a search the user has
 * already given up on. Without this, a captive-portal Wi-Fi network leaves the
 * row spinning until iOS's own minute-long timeout expires.
 */
const TIMEOUT_MS = 8000;

/**
 * The endpoint's `language` parameter takes a bare language code, so the region
 * has to come off the tag: 'pt-BR' asks for 'pt'. Sending the full tag is not
 * an error, it just quietly returns English names.
 */
const SEARCH_LANGUAGE: Record<AppLanguage, string> = {
  'pt-BR': 'pt',
  en: 'en',
};

/**
 * One row of the result list. Deliberately narrower than the payload: the
 * endpoint also returns population, elevation, feature codes and a timezone,
 * and none of it belongs in a config the widget has to decode.
 */
export interface GeocodingPlace {
  name: string;
  latitude: number;
  longitude: number;
  /** `admin1` and `country` joined, so two cities with one name are told apart. */
  subtitle: string;
}

/**
 * WHY THIS IS NOT JUST `GeocodingPlace[]`.
 *
 * An empty array would collapse two states the user needs told apart: a city
 * that does not exist, and a network that is not there. Reporting both as "no
 * results" is exactly the silent failure this repo keeps paying for elsewhere,
 * so the caller gets the difference and says it out loud.
 */
export type GeocodingOutcome =
  | { status: 'ok'; places: GeocodingPlace[] }
  | { status: 'failed' };

/**
 * Searches for a city by name. Never throws: every failure arrives as
 * `{ status: 'failed' }`, including a timeout, a DNS failure, a 5xx and a body
 * that is not the JSON we expect.
 */
export async function searchPlaces(
  query: string,
  language: AppLanguage
): Promise<GeocodingOutcome> {
  const name = query.trim();
  if (name === '') return { status: 'ok', places: [] };

  const url =
    `${ENDPOINT}?name=${encodeURIComponent(name)}` +
    `&count=${RESULT_COUNT}&language=${SEARCH_LANGUAGE[language]}&format=json`;

  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), TIMEOUT_MS);

  try {
    const response = await fetch(url, { signal: controller.signal });
    // A non-2xx body is still JSON here, but it carries an error object rather
    // than results, and parsing it would report "no city matched" for what is
    // really the service being down.
    if (!response.ok) return { status: 'failed' };
    const payload: unknown = await response.json();
    return { status: 'ok', places: parsePlaces(payload) };
  } catch {
    return { status: 'failed' };
  } finally {
    clearTimeout(timeout);
  }
}

/**
 * Open-Meteo OMITS `results` entirely when nothing matched — there is no empty
 * array to find — so an absent key is a legitimate no-results answer and not a
 * parse failure. That is also why a genuinely malformed body reads as
 * no-results here; the caller cannot tell them apart, and the difference does
 * not change what it would say.
 */
function parsePlaces(payload: unknown): GeocodingPlace[] {
  if (typeof payload !== 'object' || payload === null) return [];
  const { results } = payload as { results?: unknown };
  if (!Array.isArray(results)) return [];

  const places: GeocodingPlace[] = [];
  for (const entry of results) {
    const place = parsePlace(entry);
    // One unusable entry drops itself rather than the whole list.
    if (place !== null) places.push(place);
  }
  return places;
}

function parsePlace(entry: unknown): GeocodingPlace | null {
  if (typeof entry !== 'object' || entry === null) return null;
  const { name, latitude, longitude, admin1, country } = entry as {
    name?: unknown;
    latitude?: unknown;
    longitude?: unknown;
    admin1?: unknown;
    country?: unknown;
  };

  if (typeof name !== 'string' || name === '') return null;
  if (typeof latitude !== 'number' || !Number.isFinite(latitude)) return null;
  if (typeof longitude !== 'number' || !Number.isFinite(longitude)) return null;

  // `admin1` is missing for city-states and for countries with no first-level
  // division, so the subtitle has to survive either half being absent.
  const parts = [admin1, country].filter(
    (part): part is string => typeof part === 'string' && part !== ''
  );

  return { name, latitude, longitude, subtitle: parts.join(', ') };
}
