/**
 * Brazilian Portuguese.
 *
 * The `: Strings` annotation is the check: a missing key is TS2739, a typo'd one
 * is TS2353, and a function whose arity or parameter types drift is TS2322 on
 * that property. Parameter types are INFERRED from the contract, which is why
 * none of the functions below annotate their arguments and why each is free to
 * write its own sentence shape.
 *
 * This is the app's historical language and the one the six bundled default app
 * names are already in. Those names are user data and live in
 * `src/domain/bundledDefaults.ts`; nothing here touches them.
 */

import type { Strings } from './en';

export const ptBR: Strings = {
  sectionApps: 'Apps',
  sectionWeather: 'Clima',
  sectionPhrases: 'Frases',
  sectionAppearance: 'Aparência',
  sectionLanguage: 'Idioma',
  sectionFont: 'Fonte',
  sectionSize: 'Tamanho',
  commonOff: 'Desligado',
  commonAdd: 'Adicionar',
  commonSave: 'Salvar',
  commonCancel: 'Cancelar',
  commonDelete: 'Excluir',
  commonLoading: 'Carregando…',

  hubNoCity: 'Sem cidade',
  hubAppearanceValue: (font, size) => `${font}, ${size}`,
  hubVersion: (app, version) => `${app} ${version}`,
  hubAttribution: (provider, license) => `Dados meteorológicos por ${provider}, ${license}`,

  appsEdit: 'Editar',
  appsDone: 'Pronto',
  a11yAddApp: 'Adicionar app',
  emptyAppsTitle: 'Nenhum app ainda',
  emptyAppsBody: 'Toque em + para adicionar os que você realmente usa.',
  a11yDeleteApp: (name) => `Excluir ${name}`,
  a11yReorderApp: (name) => `Reordenar ${name}`,

  weatherEnable: 'Mostrar widget do clima',
  weatherSectionCity: 'Cidade',
  weatherForecastFor: 'Previsão para',
  weatherNoCityYet: 'Nenhuma cidade ainda',
  weatherSectionSearch: 'Buscar',
  weatherSearchHint: 'Nome da cidade',
  weatherSearchNoMatch: (query) => `Nenhuma cidade encontrada para "${query}".`,
  weatherSearchFailed:
    'Não foi possível acessar a busca de cidades. Verifique a conexão e digite de novo.',
  weatherFooterPrivacy:
    'Só a cidade é guardada, como um nome e um par de coordenadas arredondadas. O app nunca pede a sua localização.',
  weatherSectionUnits: 'Unidades',
  a11yTemperatureUnit: 'Unidade de temperatura',
  weatherFooterUnits:
    'Trocar a unidade redesenha o widget com o que ele já baixou. Não custa rede.',
  weatherPreviewFailed: 'Não foi possível carregar a previsão',
  weatherPreviewIdle: 'Escolha uma cidade para ver a previsão',

  phrasesEnable: 'Mostrar uma frase',
  phrasesSectionDuration: 'Quanto tempo ela fica',
  // Vírgula decimal, e um espaço antes da unidade.
  phrasesDurationSeconds: (seconds) => `${seconds.toFixed(1).replace('.', ',')} s`,
  phrasesSectionAdd: 'Escreva a sua',
  phrasesAddHint: 'Escreva algo curto',
  phrasesRotation: (total) => `${total} na rotação`,
  phrasesRotationUnshown: (total, unshown) =>
    unshown === 1
      ? `${total} na rotação, ${unshown} ainda não mostrada`
      : `${total} na rotação, ${unshown} ainda não mostradas`,
  a11yNotYetShown: 'Ainda não mostrada',
  a11yShownTimes: (count) =>
    count === 1 ? `Mostrada ${count} vez` : `Mostrada ${count} vezes`,
  a11yRemovePhrase: (phrase) => `Remover ${phrase}`,

  languageFooter:
    'Define a interface, as frases que já vêm no app e os nomes dos dias da semana no widget do clima. Trocar substitui as frases que vêm no app pelas do idioma escolhido e mantém cada linha que você escreveu.',

  appearanceSectionPreview: 'Prévia do widget',
  appearanceDark: 'Escuro',
  a11yAlignment: 'Alinhamento',

  formTitleEdit: 'Editar App',
  formTitleAdd: 'Adicionar App',
  formHintName: 'Nome',
  formHintUrl: (example) => `URL (${example})`,
  formChooseFromCatalog: 'Escolher do catálogo',
  formOpenFailedTitle: 'Não foi possível abrir',
  formOpenFailedBody: (url) =>
    `O iOS recusou abrir:\n\n${url}\n\nNenhum app instalado atende a esse endereço. Se o app ESTÁ instalado, o esquema dele mudou ou outro app assumiu o mesmo.`,
  formTestUrl: 'Testar esta URL',

  catalogTitle: 'Catálogo',
  catalogUnverified: 'Não verificado — pode não abrir de forma confiável.',

  notFoundTitle: 'Não encontrado',
  notFoundMessage: 'Esta tela não existe.',
  notFoundLink: (app) => `Voltar ao ${app}`,

  // Gêmea de ios/SimplePhoneWidget/WidgetViews.swift. Byte a byte.
  widgetLauncherEmpty: 'Adicione apps no Simple Phone',

  fontLabels: {
    monospaced: 'Monoespaçada',
    system: 'Sistema',
    rounded: 'Arredondada',
    serif: 'Serifada',
  },
  alignmentLabels: {
    leading: 'Esquerda',
    center: 'Centro',
    trailing: 'Direita',
  },
  sizeLabels: {
    small: 'Pequeno',
    medium: 'Médio',
    large: 'Grande',
    extraLarge: 'Extra grande',
  },
  temperatureUnitLabels: {
    celsius: 'Celsius',
    fahrenheit: 'Fahrenheit',
  },
  quoteDurationLabels: {
    instant: 'Instantâneo',
    quick: 'Rápido',
    short: 'Curto',
    medium: 'Médio',
    long: 'Longo',
  },
};
