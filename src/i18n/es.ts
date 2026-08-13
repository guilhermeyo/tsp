/**
 * Neutral Spanish. `matchLanguage` collapses es-419, es-MX and es-ES onto this
 * one catalog, so the wording avoids anything that only reads well on one side
 * of the Atlantic.
 *
 * WATCH THE LENGTH. Spanish runs 20-25% longer than English, and `DisclosureRow`
 * puts the label and its value on a single line: 'Apariencia' next to
 * 'Monoespaciada, Extra grande' is the widest thing this app renders. Check the
 * hub at the extraLarge text size before calling any change to this file done.
 */

import type { Strings } from './en';

export const es: Strings = {
  sectionApps: 'Apps',
  sectionWeather: 'Clima',
  sectionPhrases: 'Frases',
  sectionAppearance: 'Apariencia',
  sectionLanguage: 'Idioma',
  sectionFont: 'Fuente',
  sectionSize: 'Tamaño',
  commonOff: 'Desactivado',
  commonAdd: 'Añadir',
  commonSave: 'Guardar',
  commonCancel: 'Cancelar',
  commonDelete: 'Eliminar',
  commonLoading: 'Cargando…',

  hubNoCity: 'Sin ciudad',
  hubAppearanceValue: (font, size) => `${font}, ${size}`,
  hubVersion: (app, version) => `${app} ${version}`,
  hubAttribution: (provider, license) => `Datos meteorológicos de ${provider}, ${license}`,

  appsEdit: 'Editar',
  appsDone: 'Listo',
  a11yAddApp: 'Añadir app',
  emptyAppsTitle: 'Aún no hay apps',
  emptyAppsBody: 'Toca + para añadir las que de verdad usas.',
  a11yDeleteApp: (name) => `Eliminar ${name}`,
  a11yReorderApp: (name) => `Reordenar ${name}`,

  weatherEnable: 'Mostrar el widget del clima',
  weatherSectionCity: 'Ciudad',
  weatherForecastFor: 'Pronóstico para',
  weatherNoCityYet: 'Aún sin ciudad',
  weatherSectionSearch: 'Buscar',
  weatherSearchHint: 'Nombre de la ciudad',
  // Comillas angulares, que son las españolas.
  weatherSearchNoMatch: (query) => `Ninguna ciudad coincide con «${query}».`,
  weatherSearchFailed:
    'No se pudo acceder a la búsqueda de ciudades. Revisa la conexión y escribe de nuevo.',
  weatherFooterPrivacy:
    'Solo se guarda la ciudad, como un nombre y un par de coordenadas redondeadas. La app nunca pide tu ubicación.',
  weatherSectionUnits: 'Unidades',
  a11yTemperatureUnit: 'Unidad de temperatura',
  weatherFooterUnits:
    'Cambiar de unidad redibuja el widget con lo que ya descargó. No consume red.',
  weatherPreviewFailed: 'No se pudo cargar el pronóstico',
  weatherPreviewIdle: 'Elige una ciudad para ver el pronóstico',

  phrasesEnable: 'Mostrar una frase',
  phrasesSectionDuration: 'Cuánto tiempo se queda',
  // Coma decimal, y un espacio antes de la unidad.
  phrasesDurationSeconds: (seconds) => `${seconds.toFixed(1).replace('.', ',')} s`,
  phrasesSectionAdd: 'Escribe la tuya',
  phrasesAddHint: 'Que sea corta',
  phrasesRotation: (total) =>
    total === 1 ? `${total} frase en rotación` : `${total} frases en rotación`,
  // 'sin mostrar' no cambia con el número, así que solo la primera parte se
  // pluraliza.
  phrasesRotationUnshown: (total, unshown) =>
    total === 1
      ? `${total} frase en rotación, ${unshown} sin mostrar todavía`
      : `${total} frases en rotación, ${unshown} sin mostrar todavía`,
  a11yNotYetShown: 'Aún no mostrada',
  a11yShownTimes: (count) =>
    count === 1 ? `Mostrada ${count} vez` : `Mostrada ${count} veces`,
  a11yRemovePhrase: (phrase) => `Eliminar ${phrase}`,

  languageFooter:
    'Define la interfaz, las frases que trae la app y los nombres de los días en el widget del clima. Al cambiarlo, las frases que trae la app se sustituyen por las del idioma elegido y se conserva cada línea que escribiste tú.',

  appearanceSectionPreview: 'Vista previa del widget',
  appearanceDark: 'Oscuro',
  a11yAlignment: 'Alineación',

  formTitleEdit: 'Editar app',
  formTitleAdd: 'Añadir app',
  formHintName: 'Nombre',
  formHintUrl: (example) => `URL (${example})`,
  formChooseFromCatalog: 'Elegir del catálogo',
  formOpenFailedTitle: 'No se pudo abrir',
  formOpenFailedBody: (url) =>
    `iOS se negó a abrir:\n\n${url}\n\nNingún app instalado se encarga de esa dirección. Si el app SÍ está instalado, su esquema cambió u otro app se quedó con el mismo.`,
  formTestUrl: 'Probar esta URL',

  catalogTitle: 'Catálogo',
  catalogUnverified: 'Sin verificar: puede que no abra de forma fiable.',

  notFoundTitle: 'No encontrado',
  notFoundMessage: 'Esta pantalla no existe.',
  notFoundLink: (app) => `Volver a ${app}`,

  // Gemela de ios/SimplePhoneWidget/WidgetViews.swift. Carácter por carácter.
  widgetLauncherEmpty: 'Añade apps en Simple Phone',

  fontLabels: {
    monospaced: 'Monoespaciada',
    system: 'Sistema',
    rounded: 'Redondeada',
    serif: 'Serif',
  },
  alignmentLabels: {
    leading: 'Izquierda',
    center: 'Centro',
    trailing: 'Derecha',
  },
  sizeLabels: {
    small: 'Pequeño',
    medium: 'Mediano',
    large: 'Grande',
    extraLarge: 'Extra grande',
  },
  temperatureUnitLabels: {
    celsius: 'Celsius',
    fahrenheit: 'Fahrenheit',
  },
  quoteDurationLabels: {
    instant: 'Instantáneo',
    quick: 'Rápido',
    short: 'Corto',
    medium: 'Medio',
    long: 'Largo',
  },
};
