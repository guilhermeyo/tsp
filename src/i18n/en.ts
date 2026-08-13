/**
 * ENGLISH IS NOT A TRANSLATION. It is the SCHEMA.
 *
 * `Strings` is `typeof en`, and the other three catalogs are annotated with it,
 * so adding a key here breaks pt-BR, es and ja at compile time until each one
 * answers for it. That is the whole mechanism: there is no extraction step, no
 * key registry, and no way to reference a key that does not exist.
 *
 * NO `as const`. String values must widen to `string`, otherwise every
 * translation would be forced to equal the English literal. Function values
 * keep their exact signature either way, and that signature is what type-checks
 * the interpolation at the call site.
 *
 * THREE RULES THIS FILE FOLLOWS, because they are what makes the other three
 * catalogs writable at all:
 *
 * 1. No sentence is assembled by concatenation. Anything with a variable in it
 *    is a FUNCTION taking that variable, so a language may reorder the clauses,
 *    drop a plural distinction it does not have, or add one English lacks.
 * 2. Punctuation and quote glyphs live INSIDE the pattern, never around the
 *    interpolation at the call site. English quotes with "", Spanish with «»,
 *    Japanese with 「」 and ends the sentence with 。 rather than a period.
 * 3. Brand tokens are injected as parameters, never typed into a translatable
 *    string. A translator can reach the connective and never the name.
 */

import type { QuoteDuration } from '@/domain/quotes';
import type { FontChoice, RowAlignment, TemperatureUnit, TextSize } from '@/domain/types';

export const en = {
  // Shared. Every one of these is rendered from more than one screen; a section
  // name in particular appears both as a hub row and as that screen's title.
  sectionApps: 'Apps',
  sectionWeather: 'Weather',
  sectionPhrases: 'Phrases',
  sectionAppearance: 'Appearance',
  sectionLanguage: 'Language',
  sectionFont: 'Font',
  sectionSize: 'Size',
  commonOff: 'Off',
  commonAdd: 'Add',
  commonSave: 'Save',
  commonCancel: 'Cancel',
  commonDelete: 'Delete',
  commonLoading: 'Loading…',

  // Hub.
  hubNoCity: 'No city',
  /**
   * The separator is part of the sentence, not a `join`: Japanese lists with 、
   * and would otherwise inherit an ASCII comma and space.
   */
  hubAppearanceValue: (font: string, size: string) => `${font}, ${size}`,
  /**
   * `app` is the brand, injected rather than written into the pattern, so no
   * catalog can rename the product. Each language also owns the spacing between
   * the name and the number.
   */
  hubVersion: (app: string, version: string) => `${app} ${version}`,
  /**
   * CC BY 4.0 requires the creator's name and the licence notice, but not in
   * English, so the connective is free to translate. Both identifying tokens
   * arrive as parameters and are unreachable from any catalog.
   */
  hubAttribution: (provider: string, license: string) => `Weather data by ${provider}, ${license}`,

  // Apps.
  appsEdit: 'Edit',
  appsDone: 'Done',
  a11yAddApp: 'Add app',
  emptyAppsTitle: 'No apps yet',
  emptyAppsBody: 'Tap + to add the ones you actually use.',
  a11yDeleteApp: (name: string) => `Delete ${name}`,
  a11yReorderApp: (name: string) => `Reorder ${name}`,

  // Weather.
  weatherEnable: 'Show weather widget',
  weatherSectionCity: 'City',
  weatherForecastFor: 'Forecast for',
  weatherNoCityYet: 'No city yet',
  weatherSectionSearch: 'Search',
  weatherSearchHint: 'City name',
  /** The quote glyphs and the full stop belong to the language, not the caller. */
  weatherSearchNoMatch: (query: string) => `No city matched "${query}".`,
  weatherSearchFailed: 'Could not reach the city search. Check the connection and type again.',
  weatherFooterPrivacy:
    'Only the city is stored, as a name and a rounded pair of coordinates. The app never asks for your location.',
  weatherSectionUnits: 'Units',
  a11yTemperatureUnit: 'Temperature unit',
  weatherFooterUnits:
    'Switching units redraws the widget from what it already fetched. It costs no network.',
  weatherPreviewFailed: 'Could not load the forecast',
  weatherPreviewIdle: 'Choose a city to see the forecast',

  // Phrases.
  phrasesEnable: 'Show a phrase',
  phrasesSectionDuration: 'How long it stays',
  /**
   * Each language formats its own decimal separator and its own unit. `toFixed`
   * always emits a period, which is wrong for pt-BR and es, and the trailing
   * 's' is an English abbreviation that Japanese writes as 秒. No `Intl` here on
   * purpose: `style: 'unit'` is the part of the platform ICU most likely to be
   * missing from the build Hermes delegates to.
   */
  phrasesDurationSeconds: (seconds: number) => `${seconds.toFixed(1)}s`,
  phrasesSectionAdd: 'Add your own',
  phrasesAddHint: 'Keep it short',
  phrasesRotation: (total: number) => `${total} in rotation`,
  /**
   * Two independent plural categories in one sentence, which is exactly what a
   * flat string table cannot express and a function does for free. Japanese
   * simply does not branch.
   */
  phrasesRotationUnshown: (total: number, unshown: number) =>
    `${total} in rotation, ${unshown} not yet shown`,
  a11yNotYetShown: 'Not yet shown',
  a11yShownTimes: (count: number) => (count === 1 ? 'Shown once' : `Shown ${count} times`),
  a11yRemovePhrase: (phrase: string) => `Remove ${phrase}`,

  // Language.
  //
  // Rewritten from the two-language original, which said the bundled phrases are
  // replaced with "the other language's". That was only ever true while there
  // were exactly two, and it broke semantically in English before any
  // translation existed. It still has to state the side effect: switching the
  // language rewrites `quotes.items`, which is the one destructive thing any row
  // in this app does.
  languageFooter:
    'Sets the interface, the bundled phrases and the weekday names in the weather widget. Switching replaces the bundled phrases with the ones for the language you pick, and keeps every line you wrote yourself.',

  // Appearance.
  appearanceSectionPreview: 'Widget preview',
  appearanceDark: 'Dark',
  a11yAlignment: 'Alignment',

  // App form.
  formTitleEdit: 'Edit App',
  formTitleAdd: 'Add App',
  formHintName: 'Name',
  /** `example` is a URL scheme sample. Do not translate it; it is typed literally. */
  formHintUrl: (example: string) => `URL (${example})`,
  formChooseFromCatalog: 'Choose from catalog',
  formOpenFailedTitle: 'Could not open this',
  /**
   * One key, not two sentences concatenated around an injected URL. Japanese
   * puts the explanation before the address, which the old `'...' + url + '...'`
   * shape made impossible.
   */
  formOpenFailedBody: (url: string) =>
    `iOS refused to open:\n\n${url}\n\nNo installed app handles it. If the app IS installed, its scheme changed, or another app claimed the same one.`,
  formTestUrl: 'Test this URL',

  // Catalog.
  catalogTitle: 'Catalog',
  catalogUnverified: 'Unverified — may not open reliably.',

  // Not found.
  notFoundTitle: 'Not Found',
  notFoundMessage: 'This screen does not exist.',
  notFoundLink: (app: string) => `Back to ${app}`,

  /**
   * TWIN of `ios/SimplePhoneWidget/WidgetViews.swift`. The real widget renders
   * this string in another process, from a Swift switch that cannot import
   * anything from here, so the two are kept identical by hand. Changing one
   * without the other makes the in-app preview disagree with the home screen.
   */
  widgetLauncherEmpty: 'Add apps in Simple Phone',

  /**
   * The label tables. They used to live in `src/domain/types.ts` next to the
   * raw values they name, which was wrong in one specific way: the raw values
   * are the wire format Swift decodes and must never change, while the labels
   * are UI copy that changes with every language. Splitting them puts the thing
   * that varies in the file that varies.
   *
   * Nested records are fine here even though the rest of this file is flat: the
   * keys are a closed enum, so TypeScript enumerates them for every language and
   * `satisfies` makes a new enum case a compile error in THIS file first.
   */
  fontLabels: {
    monospaced: 'Monospaced',
    system: 'System',
    rounded: 'Rounded',
    serif: 'Serif',
  } satisfies Record<FontChoice, string>,
  /** Directional words. The raw values ('leading'/'trailing') are not. */
  alignmentLabels: {
    leading: 'Left',
    center: 'Center',
    trailing: 'Right',
  } satisfies Record<RowAlignment, string>,
  sizeLabels: {
    small: 'Small',
    medium: 'Medium',
    large: 'Large',
    extraLarge: 'Extra Large',
  } satisfies Record<TextSize, string>,
  temperatureUnitLabels: {
    celsius: 'Celsius',
    fahrenheit: 'Fahrenheit',
  } satisfies Record<TemperatureUnit, string>,
  quoteDurationLabels: {
    instant: 'Instant',
    quick: 'Quick',
    short: 'Short',
    medium: 'Medium',
    long: 'Long',
  } satisfies Record<QuoteDuration, string>,
};

/**
 * The contract every other catalog is checked against.
 *
 * Plain strings are `string`, so a translation is free to differ. Parameterised
 * entries keep their arity and their parameter types, so a catalog that drops an
 * argument or takes a `string` where the caller passes a `number` fails to
 * compile.
 */
export type Strings = typeof en;
