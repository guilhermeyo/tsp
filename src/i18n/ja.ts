/**
 * Japanese.
 *
 * Japanese has no plural category, so none of the counted strings below branch.
 * That is not a missing translation: a function that ignores the distinction is
 * the correct answer, and it is why these are functions rather than templates
 * with a plural engine bolted on.
 *
 * Punctuation is Japanese throughout, because it lives inside the pattern:
 * 、for lists, 「」around a quoted query, 。to end a sentence, and full-width
 * parentheses （） around Japanese text. ASCII stays around ASCII: URLs, version
 * numbers and the brand keep the spacing they would have on their own.
 *
 * These strings run much SHORTER than English, which is only a problem in the
 * opposite direction from Spanish: a two-character label in a segmented control
 * can look unintentionally sparse. Check Appearance on device.
 */

import type { Strings } from './en';

export const ja: Strings = {
  sectionApps: 'アプリ',
  sectionWeather: '天気',
  sectionPhrases: 'フレーズ',
  sectionAppearance: '外観',
  sectionLanguage: '言語',
  sectionFont: 'フォント',
  sectionSize: 'サイズ',
  commonOff: 'オフ',
  commonAdd: '追加',
  commonSave: '保存',
  commonCancel: 'キャンセル',
  commonDelete: '削除',
  commonLoading: '読み込み中…',

  hubNoCity: '都市なし',
  // 読点。ASCII のカンマとスペースではない。
  hubAppearanceValue: (font, size) => `${font}、${size}`,
  // ブランド名もバージョン番号もラテン文字なので、間は半角スペースのまま。
  hubVersion: (app, version) => `${app} ${version}`,
  hubAttribution: (provider, license) => `${provider}による気象データ、${license}`,

  appsEdit: '編集',
  appsDone: '完了',
  a11yAddApp: 'アプリを追加',
  emptyAppsTitle: 'アプリがありません',
  emptyAppsBody: '「+」をタップして、本当に使うアプリだけを追加してください。',
  a11yDeleteApp: (name) => `${name}を削除`,
  a11yReorderApp: (name) => `${name}を並べ替え`,

  weatherEnable: '天気ウィジェットを表示',
  weatherSectionCity: '都市',
  weatherForecastFor: '予報の対象',
  weatherNoCityYet: 'まだ都市がありません',
  weatherSectionSearch: '検索',
  weatherSearchHint: '都市名',
  weatherSearchNoMatch: (query) => `「${query}」に一致する都市はありません。`,
  weatherSearchFailed: '都市検索に接続できませんでした。接続を確認して、もう一度入力してください。',
  weatherFooterPrivacy:
    '保存されるのは都市名と、丸めた座標だけです。このアプリが位置情報を求めることはありません。',
  weatherSectionUnits: '単位',
  a11yTemperatureUnit: '温度の単位',
  weatherFooterUnits:
    '単位を切り替えると、取得済みのデータでウィジェットを描き直します。通信は発生しません。',
  weatherPreviewFailed: '予報を読み込めませんでした',
  weatherPreviewIdle: '都市を選ぶと予報が表示されます',

  phrasesEnable: 'フレーズを表示',
  phrasesSectionDuration: '表示し続ける時間',
  // 小数点はピリオド、単位は秒、数字との間は詰める。
  phrasesDurationSeconds: (seconds) => `${seconds.toFixed(1)}秒`,
  phrasesSectionAdd: '自分のフレーズを追加',
  phrasesAddHint: '短く書く',
  phrasesRotation: (total) => `${total}件をローテーション`,
  phrasesRotationUnshown: (total, unshown) =>
    `${total}件をローテーション、うち${unshown}件は未表示`,
  a11yNotYetShown: '未表示',
  a11yShownTimes: (count) => `${count}回表示`,
  a11yRemovePhrase: (phrase) => `${phrase}を削除`,

  languageFooter:
    'インターフェース、付属のフレーズ、天気ウィジェットの曜日名を切り替えます。変更すると付属のフレーズは選んだ言語のものに入れ替わり、自分で書いた行はすべて残ります。',

  appearanceSectionPreview: 'ウィジェットのプレビュー',
  appearanceDark: 'ダーク',
  a11yAlignment: '配置',

  formTitleEdit: 'アプリを編集',
  formTitleAdd: 'アプリを追加',
  formHintName: '名前',
  // 例そのものは翻訳しない。全角括弧で囲うだけ。
  formHintUrl: (example) => `URL（${example}）`,
  formChooseFromCatalog: 'カタログから選ぶ',
  formOpenFailedTitle: '開けませんでした',
  // 英語と語順が逆。説明が先で、アドレスが後ではなく先頭に来る形を保つため、
  // 文全体をひとつのキーとして書き直している。
  formOpenFailedBody: (url) =>
    `次のアドレスをiOSが開けませんでした:\n\n${url}\n\nこれを処理できるアプリがインストールされていません。インストール済みの場合は、スキームが変わったか、別のアプリが同じスキームを取得しています。`,
  formTestUrl: 'このURLを試す',

  catalogTitle: 'カタログ',
  catalogUnverified: '未確認：正しく開かない場合があります。',

  notFoundTitle: '見つかりません',
  notFoundMessage: 'この画面は存在しません。',
  notFoundLink: (app) => `${app}に戻る`,

  // ios/SimplePhoneWidget/WidgetViews.swift と一字一句同じ。
  widgetLauncherEmpty: 'Simple Phoneでアプリを追加',

  fontLabels: {
    monospaced: '等幅',
    system: 'システム',
    rounded: '丸ゴシック',
    serif: 'セリフ',
  },
  alignmentLabels: {
    leading: '左',
    center: '中央',
    trailing: '右',
  },
  sizeLabels: {
    small: '小',
    medium: '中',
    large: '大',
    extraLarge: '特大',
  },
  temperatureUnitLabels: {
    celsius: '摂氏',
    fahrenheit: '華氏',
  },
  quoteDurationLabels: {
    instant: '即時',
    quick: '一瞬',
    short: '短い',
    medium: '中くらい',
    long: '長い',
  },
};
