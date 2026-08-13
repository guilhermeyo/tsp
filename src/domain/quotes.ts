/**
 * The phrase shown during the relay.
 *
 * A widget tap always launches this app before the target one, and that gap
 * cannot be removed (see AppDelegate.swift). It can be spent on something,
 * though: one line, held for a beat, between the impulse and the app.
 *
 * WHY THEY ARE SHORT. The line is on screen for about a second and a half while
 * the user is already reaching for something else. Anything longer than a
 * glance is not read, it is skipped, and a skipped line is just a slower
 * launcher. Most of these are under six words on purpose.
 *
 * WHY THEY LIVE ONLY HERE. The native relay does not carry this catalog. The
 * app resolves the active list into the shared config, and Swift reads that,
 * so these 200 lines exist in exactly one place and the Swift side stays a
 * dozen lines of plist reading.
 */

export type QuoteLanguage = 'pt-BR' | 'en';

/**
 * How long the phrase is held before the target app is asked to open.
 *
 * A setting rather than a constant because the right value is a matter of
 * taste and of what the phrase is FOR. Treated as a pause it wants to be long;
 * treated as a launcher it wants to be gone. Only the person tapping it forty
 * times a day can say.
 *
 * The felt pause is longer than the number: iOS spends its own moment on the
 * app-to-app transition after this elapses.
 */
export type QuoteDuration = 'instant' | 'quick' | 'short' | 'medium' | 'long';

export const QUOTE_DURATIONS: readonly QuoteDuration[] = [
  'instant',
  'quick',
  'short',
  'medium',
  'long',
];

/**
 * `instant` is zero ADDED delay, not a very small one, and it is the default.
 *
 * The phrase is a cover, not a pause. Its job is that the app list never
 * appears during the handoff, and the handoff already takes a few hundred
 * milliseconds of iOS transition that nothing can shorten. Painting a phrase
 * into exactly that window costs nothing and removes the only thing anyone
 * disliked about the relay.
 *
 * The longer values remain for the other reading of the feature, where the
 * phrase is a deliberate beat of friction between the impulse and the app.
 */
export const QUOTE_DURATION_MS: Record<QuoteDuration, number> = {
  instant: 0,
  quick: 800,
  short: 1500,
  medium: 2600,
  long: 4000,
};

export const QUOTE_DURATION_LABEL: Record<QuoteDuration, string> = {
  instant: 'Instant',
  quick: 'Quick',
  short: 'Short',
  medium: 'Medium',
  long: 'Long',
};

export function isQuoteDuration(value: unknown): value is QuoteDuration {
  return (
    value === 'instant' ||
    value === 'quick' ||
    value === 'short' ||
    value === 'medium' ||
    value === 'long'
  );
}

export const QUOTE_LANGUAGES: readonly QuoteLanguage[] = ['pt-BR', 'en'];

export function isQuoteLanguage(value: unknown): value is QuoteLanguage {
  return value === 'pt-BR' || value === 'en';
}

/** Label for the language picker. Shown in the user's own language, not translated. */
export const QUOTE_LANGUAGE_LABEL: Record<QuoteLanguage, string> = {
  'pt-BR': 'Português',
  en: 'English',
};

const PT_BR: readonly string[] = [
  'Comece pequeno, comece agora.',
  'Feito é melhor que perfeito.',
  'Um passo já muda a direção.',
  'O difícil fica fácil com repetição.',
  'Sua atenção é o seu tempo.',
  'Escolha uma coisa. Termine.',
  'Constância vence intensidade.',
  'Hoje conta mais que segunda.',
  'Plano no papel não anda.',
  'Menos abas, mais avanço.',
  'Disciplina é lembrar do que você quer.',
  'Ninguém acerta sem tentar feio antes.',
  'A pressa atrapalha, o ritmo não.',
  'Você não precisa de motivação, precisa começar.',
  'Uma hora focada vale um dia disperso.',
  'Guarde energia para o que importa.',
  'O silêncio também é produtivo.',
  'Faça a parte chata primeiro.',
  'Progresso não é linha reta.',
  'Descansar é parte do trabalho.',
  'Compare com quem você era ontem.',
  'O tédio costuma vir antes da ideia.',
  'Não confunda movimento com direção.',
  'Termine o que você já começou.',
  'A dúvida some quando a mão trabalha.',
  'Grandes coisas são feitas de terças-feiras.',
  'Aprender é lento e vale a pena.',
  'Cuide do corpo, ele carrega o resto.',
  'Diga não para poder dizer sim.',
  'O que você repete, você vira.',
  'Comece pela versão feia.',
  'Uma página por dia vira livro.',
  'Sua cabeça precisa de espaço vazio.',
  'Desligue antes de precisar.',
  'Presença é raridade agora.',
  'Nada rende como dormir bem.',
  'Escolha o incômodo que vale a pena.',
  'Menos promessas, mais entregas.',
  'A meta é o hábito.',
  'Você já fez coisa mais difícil.',
  'Simples não é fácil, mas dura.',
  'O tempo passa igual, ocupado ou não.',
  'Faça hoje o que trava o amanhã.',
  'Curiosidade rende mais que talento.',
  'Corrija rápido, insista devagar.',
  'Vale mais uma pergunta boa.',
  'Se está travado, diminua o pedaço.',
  'Ninguém está olhando tanto quanto você pensa.',
  'Comece antes de se sentir pronto.',
  'Um dia ruim não apaga o mês.',
  'Anote, sua memória mente.',
  'Melhor um pouco todo dia.',
  'Pare enquanto ainda sabe o próximo passo.',
  'Trabalho profundo pede telefone longe.',
  'O caminho aparece andando.',
  'Você decide o que merece atenção.',
  'Ler devagar é ler duas vezes.',
  'Confie mais no processo, menos no humor.',
  'A vontade vem depois do início.',
  'Erro barato é aprendizado rápido.',
  'Some da internet, apareça na vida.',
  'Uma tarefa por vez já é bastante.',
  'Preparação evita pressa.',
  'Boa noite de sono resolve metade.',
  'Faça pelo você de um ano.',
  'Consistência é chata e funciona.',
  'Diminua a meta até virar fácil.',
  'Você não precisa responder agora.',
  'Espere o impulso passar.',
  'Trocar de tarefa custa caro.',
  'O melhor momento é agora.',
  'Se importa, agende.',
  'Nada muda se nada muda.',
  'Termine antes de melhorar.',
  'Atenção dividida não é atenção.',
  'Você é o que você faz repetido.',
  'Ambição sem rotina é só desejo.',
  'A pausa também é decisão.',
  'Guarde o dia bom.',
  'Comece pelo mais assustador.',
  'Ideia sem prazo é fantasia.',
  'Foco é escolher o que ignorar.',
  'Faça caber, não faça esperar.',
  'Você aprende fazendo errado.',
  'Ritmo bate pressa todo dia.',
  'Antes de abrir, respira.',
  'Menos notificação, mais vida.',
  'Sua rotina é seu projeto.',
  'Feche o que não está usando.',
  'Andar devagar ainda é andar.',
  'Escolha a versão simples.',
  'O corpo avisa antes da cabeça.',
  'Trabalhe no que ninguém vê.',
  'A prática desfaz o medo.',
  'Guarde tempo para pensar.',
  'Boa decisão pede boa noite antes.',
  'Duas horas mudam a semana.',
  'Você pode parar quando quiser.',
  'Faça a próxima coisa certa.',
  'Menos é quase sempre o suficiente.',
  'O tempo que você tem é agora.',
];

const EN: readonly string[] = [
  'Start small, start now.',
  'Done beats perfect.',
  'One step changes the direction.',
  'Hard turns easy with repetition.',
  'Your attention is your time.',
  'Pick one thing. Finish it.',
  'Consistency beats intensity.',
  'Today counts more than Monday.',
  'A plan is worth nothing on paper.',
  'Fewer tabs, more progress.',
  'Discipline is remembering what you want.',
  'Nobody gets it right without failing first.',
  'Hurry hurts. Rhythm does not.',
  'You need to begin, not to feel ready.',
  'One focused hour beats a scattered day.',
  'Save your energy for what matters.',
  'Quiet is productive too.',
  'Do the boring part first.',
  'Progress is not a straight line.',
  'Rest is part of the work.',
  'Compare yourself to yesterday.',
  'Boredom usually comes before the idea.',
  'Motion is not direction.',
  'Finish what you already started.',
  'Doubt fades once your hands move.',
  'Big things are made of Tuesdays.',
  'Learning is slow and worth it.',
  'Take care of the body carrying you.',
  'Say no so you can say yes.',
  'You become what you repeat.',
  'Start with the ugly version.',
  'A page a day becomes a book.',
  'Your head needs empty space.',
  'Switch off before you have to.',
  'Being present is rare now.',
  'Nothing pays like real sleep.',
  'Choose the discomfort worth having.',
  'Fewer promises, more delivery.',
  'The goal is the habit.',
  'You have done harder things.',
  'Simple is not easy, but it lasts.',
  'Time passes either way.',
  'Do today what blocks tomorrow.',
  'Curiosity outperforms talent.',
  'Correct fast, persist slowly.',
  'A better question is worth more.',
  'If you are stuck, cut it smaller.',
  'Nobody is watching that closely.',
  'Begin before you feel ready.',
  'One bad day does not erase the month.',
  'Write it down. Memory lies.',
  'A little every day wins.',
  'Stop while you know the next step.',
  'Deep work wants the phone far away.',
  'The path shows up while walking.',
  'You decide what deserves attention.',
  'Reading slowly is reading twice.',
  'Trust the process over the mood.',
  'The urge arrives after the start.',
  'Cheap mistakes teach fast.',
  'Leave the feed, join your life.',
  'One task at a time is plenty.',
  'Preparation prevents panic.',
  'A good night fixes half of it.',
  'Do it for next year you.',
  'Consistency is boring and it works.',
  'Shrink the goal until it is easy.',
  'You do not have to answer now.',
  'Let the impulse pass.',
  'Switching tasks is expensive.',
  'The best time is now.',
  'If it matters, schedule it.',
  'Nothing changes if nothing changes.',
  'Finish before you improve.',
  'Divided attention is not attention.',
  'You are what you do repeatedly.',
  'Ambition without routine is just wishing.',
  'Pausing is a decision too.',
  'Keep the good day.',
  'Start with the scariest one.',
  'An idea without a date is wishing.',
  'Focus is choosing what to ignore.',
  'Make room, do not make it wait.',
  'You learn by getting it wrong.',
  'Rhythm beats rush every time.',
  'Breathe before you open it.',
  'Fewer notifications, more life.',
  'Your routine is your project.',
  'Close what you are not using.',
  'Walking slowly is still walking.',
  'Choose the simple version.',
  'The body warns before the mind.',
  'Work on what nobody sees.',
  'Practice undoes fear.',
  'Keep time for thinking.',
  'Good decisions want good sleep first.',
  'A two hour block changes the week.',
  'You can stop whenever you want.',
  'Do the next right thing.',
  'Less is usually enough.',
  'The only time you have is now.',
];

export const BUNDLED_QUOTES: Record<QuoteLanguage, readonly string[]> = {
  'pt-BR': PT_BR,
  en: EN,
};
