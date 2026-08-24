# Flashcards — Project Documentation

> Полный контекст проекта для человека или ИИ. Прочитай этот файл — и можно работать над любой частью без дополнительного изучения кода.
> Стиль: машинно-ориентированный (таблицы, ID, селекторы). Текст RU, заголовки EN.

---

## Table of Contents

1. [Overview](#1-overview)
2. [File Structure](#2-file-structure)
3. [Architecture](#3-architecture)
4. [Design System](#4-design-system)
5. [Data & Storage](#5-data--storage)
6. [Feature Logic](#6-feature-logic)
7. [Tests](#7-tests)
8. [Decisions Log](#8-decisions-log)
9. [Pitfalls](#9-pitfalls)
10. [Product Principles](#10-product-principles)
11. [Roadmap Priorities](#11-roadmap-priorities)
12. [Conventions](#12-conventions)

---

## 1. Overview

Приложение-флэшкарточки «Карточки» в эстетике школьной тетради (бумага, поля, дырки от скоросшивателя, васи-лента, штампы).

| Свойство | Значение |
|---|---|
| Стек | Vanilla HTML/CSS/JS, **без фреймворков, сборки, зависимостей, модулей** |
| Запуск | Открыть `index.html` напрямую (`file://`) или любой static-сервер |
| Данные | Только `localStorage`, офлайн-first, сервера нет |
| Шрифты | PT Sans + PT Serif с Google Fonts (`display=swap`), фолбэки Segoe UI / Georgia |
| Язык UI | Русский (строки захардкожены в JS/HTML) |
| Палитры | 10, темы светлая/тёмная, выбор сохраняется |
| Тесты | 22 PowerShell CDP-скрипта вне репозитория (`%TEMP%\opencode\`), ~648 проверок |

---

## 2. File Structure

| Файл | Строк | Роль |
|---|---|---|
| `index.html` | 475 | Вся разметка: sidebar, main, 10 бэкдропов + tour-tip + theme-bloom, инлайн-скрипт восстановления темы в `<head>`, favicon — inline SVG data-URI |
| `style.css` | 2758 | Все стили; секции с баннерами `/* ==== Название ==== */` |
| `storage.js` | 277 | `state`, нормализация, persist, статистика-хелперы, uid, даты |
| `modal.js` | 169 | Generic-модалка на Promise, focus-trap, lockScroll, showLayer/hideLayer — единый паттерн всех оверлеев, настройки вида |
| `ui.js` | 517 | `PALETTE_META` (единый источник палитр), рендеры списков, поиск, applyAppearance + bloom |
| `study.js` | 719 | Перемешивание, флип, навигация, статусы, итог раунда, focus-режим, квиз + его фуллскрин |
| `menu.js` | 385 | Главное меню, выбор колоды, действия колоды, обучающий тур |
| `stats.js` | 183 | Окно статистики, дневные бары, сессии колоды |
| `library.js` | 155 | Демо-колоды (данные) + модалка библиотеки |
| `data.js` | 250 | Экспорт/импорт базы и колод (JSON+CSV), диалог слияния, toast-подтверждения |
| `images.js` | 91 | IndexedDB-хранилище картинок, клиентское сжатие 480px WebP q0.6 |
| `app.js` | 590 | Массовый ввод, CRUD колод/карточек, поиск/квиз-биндинги, маршрутизация фокусов, `bindEvents()`, инициализация |

**Порядок загрузки** (все перед `</body>`, обычные скрипты):
`storage.js → modal.js → ui.js → study.js → menu.js → stats.js → library.js → data.js → images.js → app.js`

Автозапуск при загрузке: `menu.js` → `bindMenuEvents()`, `stats.js` → `bindStatsEvents()`, `library.js` → биндинги библиотеки. Всё остальное запускает инициализация в конце `app.js`:

```js
loadState(); renderThemeDots(); bindAutoTheme(); bindEvents(); syncAppearanceButtons(); render(); openMenu();
```

Инлайн-скрипт в `<head>` (до CSS-рендера) восстанавливает тему из localStorage, чтобы не было вспышки: читает `flashcards-mode`/`flashcards-palette`, подхватывает legacy-ключ `flashcards-theme` (`night`→dark+ember, `orange`→ember), ставит `data-mode`/`data-palette` на `<html>`.

---

## 3. Architecture

### 3.1 Communication Model

- Все функции — **глобальные**, вызываются между файлами напрямую (без модулей намеренно — см. Decisions Log).
- Единственная точка полного перерендера — `render()` (ui.js). Локальные обновления (статус карточки, статистика) идут точечно: `updateCardRowStatus()`, `renderStats()`.
- Списки рендерятся через `DocumentFragment` одним append'ом.
- События строк списка карточек **делегированы контейнеру** (`bindCardRowsDelegation`: click/DnD на `#card-rows`) — рендер не плодит листенеры, масштабируется линейно.

### 3.2 Global State (storage.js)

```js
state = {
  decks: [{ id, name, twoSided }],          // twoSided: учить в обе стороны (id#rev в studyOrder)
  cards: [{ id, deckId, question, answer, status }],  // status: new|known|unknown
  selectedDeckId: string|null,
  cardFilter: "all"|"new"|"known"|"unknown",// НЕ персистится
  searchQuery: string,                      // НЕ персистится, живой поиск по карточкам
  tab: "edit"|"study",                      // НЕ персистится
  studyMode: "flip"|"quiz",                 // НЕ персистится, режим панели «Учить»
  studyOrder: [entry], studyIndex: 0, flipped: false,     // entry = cardId или cardId+"#rev"; НЕ персистится
  today: { date: "YYYY-MM-DD", known, unknown },
  history: { [deckId]: { [date]: { known, unknown } } },
  sessions: [{ deckId, date, known, unknown }],
}
```

`saveState()` пишет только: `decks, cards, selectedDeckId, today, history, sessions`.

### 3.3 DOM Contract — все ID

| Область | ID | Назначение |
|---|---|---|
| Sidebar | `new-deck-btn`, `deck-list`, `settings-btn` | создание колоды, список, настройки |
| Empty | `empty-state`, `empty-new-deck-btn`, `empty-menu-btn` | экран «Пока пусто» |
| Workspace | `workspace`, `deck-title`, `stats`, `menu-back-btn`, `rename-deck-btn`, `delete-deck-btn` | шапка колоды |
| Tabs | `tab-edit`, `tab-study`, `panel-edit`, `panel-study` | вкладки (role=tablist) |
| Edit | `card-form`, `card-id`(hidden), `card-question`, `card-answer`, `image-btn`, `card-image`(hidden file), `image-preview`, `image-thumb`, `image-clear`, `save-card-btn`, `bulk-btn`, `cancel-edit-btn`, `card-search-row`, `card-search`, `card-search-clear`, `card-filters`, `card-rows` | форма (+картинка) + поиск + фильтры + список |
| Study | `study-empty`, `study-board`, `study-modes`, `study-mode-flip`, `study-mode-quiz`, `two-sided-btn`, `flip-area`, `study-meta`, `flashcard`, `flashcard-question`, `flashcard-answer`, `focus-btn`, `prev-card-btn`, `next-card-btn`, `mark-known-btn`, `mark-unknown-btn` | доска изучения (на обеих гранях карты — без-ID спаны `.face-speak` с SVG-иконкой озвучки) |
| Quiz | `quiz-start`, `quiz-area`, `quiz-meta`, `quiz-fill`, `quiz-question`, `quiz-options`, `quiz-focus-btn`, `quiz-next` | квиз-режим внутри «Учить» (+фуллскрин) |
| Focus | `focus-backdrop`, `focus-meta`, `focus-exit`, `focus-wrap`, `focus-controls`, `focus-prev`, `focus-next`, `focus-known`, `focus-unknown` | полноэкранный режим |
| Settings | `settings-backdrop`, `settings-title`, `mode-switch`, `theme-dots`, `fontsize-switch`, `settings-close` | модалка вида |
| Modal | `modal-backdrop`, `modal-kicker`, `modal-title`, `modal-text`, `modal-field`, `modal-input`, `modal-cancel`, `modal-ok` | универсальная модалка (Promise) |
| Menu | `menu-backdrop`, `menu-title`, `menu-close`, `menu-today`, `menu-today-stats`, `menu-streak`, `menu-study-btn`, `menu-cards-btn`, `menu-library-btn`, `menu-stats-btn`, `menu-settings-btn`, `menu-mode-switch`, `menu-theme-dots` | главное меню |
| Deck pick | `deck-pick-backdrop`, `deck-pick-kicker`, `deck-pick-title`, `deck-pick-new`, `deck-pick-list`, `deck-pick-cancel` | выбор колоды |
| Deck pop | `menu-pop-backdrop`, `menu-pop-kicker`, `menu-pop-title`, `menu-pop-actions`, `menu-pop-cancel` | действия колоды |
| Library | `library-backdrop`, `library-list`, `library-cancel` | демо-колоды |
| Bulk | `bulk-backdrop`, `bulk-hint`, `bulk-input`, `bulk-feedback`, `bulk-cancel`, `bulk-ok` | массовый ввод |
| Summary | `summary-backdrop`, `summary-line`, `summary-fill`, `summary-repeat`, `summary-stats`, `summary-menu` | итог раунда |
| Stats | `stats-backdrop`, `stats-close`, `stats-main`, `stats-total`, `stats-today`, `stats-alltime`, `stats-list`, `stats-empty`, `stats-go-study`, `stats-deck`, `stats-back`, `stats-deck-title`, `stats-sessions` | окно статистики |
| Tour | `tour-tip`, `tour-text`, `tour-skip`, `tour-next` | обучающий тур |
| Effects | `theme-bloom`, `storage-alert` | вспышка при смене темы; несущий баннер сбоя сохранения (`role=alert`, авто-скрытие 6с) |
| Статичные надзаголовки/титулы | `deck-kicker`, `settings-title`, `deck-pick-kicker`, `deck-pick-title`, `menu-pop-kicker`, `menu-pop-title`, `library-kicker`, `library-title`, `bulk-kicker`, `bulk-title`, `summary-kicker`, `summary-title`, `stats-title`, `stats-deck-kicker` | текстовые узлы, заполняются статикой в HTML либо JS при открытии |

Итого 158 ID — полный список совпадает с разметкой (проверено grep'ом по `id="`).

Ключевые классы-состояния: `.hidden` (display:none!important), `.is-open` (бэкдропы), `.is-active` (вкладки/фильтры/точки/колоды), `.is-flipped` / `.was-flipped` / `.is-swap` (карта), `.modal-open` (body, блокировка скролла), `.warn` (bulk-feedback), `.tour-highlight`.

### 3.4 Overlay Pattern (единый для всех окон)

```
.modal-backdrop { opacity:0; visibility:hidden; pointer-events:none;
                  transition: opacity .28s var(--ease), visibility 0s linear .28s }
.is-open        { opacity:1; visibility:visible; pointer-events:auto }
```

Открытие всегда через `showLayer(backdrop)` (= classList.add + reflow), затем `lockScroll(true)` и focus(). Закрытие — `hideLayer(backdrop)`.
Закрытие: снять класс, `lockScroll(false)`, вернуть фокус на триггер (`canFocus(el)` проверяет подключённость и видимость).

Z-index шкала: `menu-backdrop` 40 · `modal-backdrop` 40 · `stats-backdrop` 45 · `settings-backdrop` 46 · `focus-backdrop` 60 · `tour-tip` 70 · `theme-bloom` 300. Тайминги появления: модалки и focus — 0.28s, меню и статистика — 0.3s.

Escape: у каждого бэкдропа свой keydown со `stopPropagation()`; плюс документный fallback `closeTopModal()` (input-модалка → настройки). Tab внутри окна — `trapTabKey(backdrop, event)` по списку `getFocusable()`.

### 3.5 Focus Mode (study.js)

Узел `#flashcard` **физически перемещается** `appendChild` между `.flashcard-wrap` (дом) и `#focus-wrap` (полноэкран). Выход возвращает в первый `.flashcard-wrap` внутри `#study-board`. Кнопки дублированы (`mark-*` / `focus-*`), `aria-pressed` синхронизируется в `syncPressState(card)`.

### 3.6 Round Lifecycle

```
startStudyShuffle() → beginRound(shuffle(ids))  // studyOrder, счётчики reset
  ↳ flipCard(): первый флип карточки за раунд → status="unknown",
    today.unknown++, history[deck][today]++, flipCounted/sessionMarked.add(id)
  ↳ markStatus("known"|"unknown"): sessionMarked.add(id), today/history,
    при известном flipCounted двойной счёт unknown не идёт
  ↳ moveStudy(±1): индекс по модулю; next на последней при полном раунде → summary
isRoundComplete(): sessionMarked.size >= studyOrder.length
showSummary(): exitFocusMode → запись session → окно итога
repeatStudy(): dataset.mode="unknown"|"all" → beginRound(отфильтрованные id)
```

Смена карточки: класс `is-swap` снимается по `animationend` ИЛИ таймеру 500ms (страховка, CSS 420ms); `swapCleanup` против гонок при быстрых кликах.

### 3.7 Global Function Map

| Файл | Функции |
|---|---|
| storage.js | `dateKey`, `todayDateKey`, `resetTodayIfNeeded`, `getTodayStats`, `uid`, `isPlainObject`, `migrateSchema`, `normalizeHistory`, `normalizeSessions`, `normalizeState`, `showStorageAlert`, `loadState`, `saveState`, `selectedDeck`, `cardsInDeck`, `recordStudy`, `recordSession`, `getDeckHistory`, `getAllTimeStats`, `computeStreak` |
| modal.js | `getFocusable`, `lockScroll`, `trapTabKey`, `showLayer`, `hideLayer`, `openModal` (→ Promise), `canFocus`, `closeModal`, `openSettingsModal`, `closeSettingsModal`, `closeTopModal`, `bindModalEvents` |
| ui.js | `renderThemeDots`, `makeEl`, `badgeFor`, `cardMatchesFilter`, `filterLabel`, `searchMatches`, `appendHighlighted`, `clearCardSearch`, `clearDropIndicators`, `moveCardWithinDeck`, `bindCardRowsDelegation`, `renderDeckList`, `renderCardFilters`, `renderCardRows`, `updateCardRowStatus`, `renderStats`, `resetCardForm`, `render`, `systemDark`, `modePref`, `effectiveMode`, `palettePref`, `fontSizePref`, `applyFontSize`, `syncFontButtons`, `bindAutoTheme`, `syncAppearanceButtons`, `applyAppearance` |
| study.js | `bezProgress`, `currentAngle`, `flipHost`, `clearLift`, `killFlipAnims`, `startFlipAnimation`, `shuffle`, `reduceMotion`, `entryId`, `entryRev`, `buildStudyEntries`, `beginRound`, `startStudyShuffle`, `resetStudy`, `setStudyMode`, `syncTwoSidedBtn`, `toggleTwoSided`, `syncStudyView`, `enterQuizFocus`, `exitQuizFocus`, `enterFocusMode`, `exitFocusMode`, `currentStudyCards`, `setTab`, `syncPressState`, `showStudyCard`, `flipCard`, `isRoundComplete`, `moveStudy`, `markStatus`, `pickRuVoice`, `speakText`, `speakFace`, `stopSpeech`, `updateQuizMeta`, `buildOptions`, `renderQuizQuestion`, `answerQuiz` (check-draw), `nextQuiz`, `startQuiz`, `beginQuiz`, `finishQuiz`, `launchConfetti`, `openSummaryOverlay`, `showSummary`, `closeSummary`, `repeatStudy` |
| menu.js | `pluralDays`, `renderMenu`, `openMenu`, `closeMenu`, `closeAllMenus`, `openMenuPop`, `closeMenuPop`, `renderDeckPicker`, `openDeckPicker`, `closeDeckPicker`, `openDeckActions`, `menuStudy`, `menuOpenCards`, `bigStudy`, `openFirstDeck`, `showTour`, `renderTourStep`, `positionTourTip`, `nextTourStep`, `finishTour`, `hideTour`, `bindMenuEvents` |
| stats.js | `lastDays`, `countUp`, `openStats`, `closeStats`, `renderDayBars` (каскад), `renderStatsWindow` (count-up), `openDeckStats`, `closeDeckStats`, `bindStatsEvents` |
| library.js | `addedDemoIds`, `markDemoAdded`, `renderLibrary`, `openLibrary`, `closeLibrary`, `addDemoDeck` |
| images.js | imgOpen, imgTx, imgReq, imgGet, imgPut, imgDelete, imgGcOrphans, loadImageElement, compressImageFile (IndexedDB + сжатие) |
| data.js | `todayStamp`, `slugifyName`, `downloadBlob`, `buildBackupPayload`, `exportBaseJson`, `exportDeckJson`, `csvField`, `csvSplitLine`, `exportBaseCsv`, `looksLikeCsv`, `parseImportJson`, `parseImportCsv`, `openDataDialog`, `closeDataDialog`, `summarizeImport`, `handleImportText`, `applyCsvImport`, `applyImport`, `bindDataEvents` |
| app.js | `startEditCard`, `splitBulkPair`, `parseBulkLines`, `openBulkInput`, `closeBulkInput`, `applyBulkInput`, `createDeck`, `renameDeck`, `deleteDeck`, `resetDeckProgress`, `deleteCard`, `saveCard`, `finishDeleteCard`, `bindEvents`, `bindMotionExtras`, `bindMotionExtras` |

### 3.8 Constants

| Константа | Значение | Где |
|---|---|---|
| `STORAGE_KEY` / `MODE_KEY` / `PALETTE_KEY` / `ONBOARD_KEY` | `flashcards-app-v1` / `flashcards-mode` / `flashcards-palette` / `flashcards-onboarded` | storage.js |
| `DEMO_KEY` | `flashcards-demos` (массив id добавленных демо-колод) | library.js |
| `VALID_STATUSES` | Set(`new`, `known`, `unknown`) | storage.js |
| `MAX_NAME_LENGTH` | 80 | storage.js |
| `MAX_SESSIONS` | 200 | storage.js + data.js: кап сессий, при merge сортировка по дате перед усечением |
| `CORRUPT_KEY` | `flashcards-app-v1-corrupt` — бэкап непарсящегося payload; пишется в `loadState` при ошибке разбора + warn-toast | storage.js |
| `BULK_SEPARATOR` | `"="` | app.js |
| `SCHEMA_VERSION` | `1` — поле `v` в payload базы; `migrateSchema` пропускает legacy и будущие версии без краша | storage.js |
| `EXPORT_VERSION` / cap sessions | `2` / последние 200 записей (обрезка в `recordSession`) | data.js / storage.js |
| `SWAP_DURATION` | 500 (ms, JS-страховка; CSS-анимация 420) | study.js |
| `DEMO_DECKS` | 3 демо-колоды: английский 30 карт, столицы 12, элементы 15 | library.js |

Модульные переменные-состояния: `swapCleanup`, `flipCounted`, `sessionMarked`, `statusCounted`, `focusMode`, `focusTrigger`, `quizActive`, `quizAnswered`, `quizOrder`, `quizIndex`, `quizRight`, `quizWrong`, `quizRetry`, `quizFullscreen`, `flipAnims`, `flipRun` (study.js); `menuPopTrigger`, `tourStep`, `tourSteps` (menu.js); `modalResolver`, `modalTrigger`, `settingsTrigger` (modal.js); `libraryTrigger` (library.js); `bulkTrigger`, `dragCardId`, `rowsBound`, `hadMarks`, `pendingImage`, `editImageId` (app.js); `prevDeckId` (ui.js). Константы анимации флипа: `FLIP_BEZIER=[0.45,0,0.25,1]`, `FLIP_DUR=620`.

---

## 4. Design System

### 4.1 Concept

Школьная тетрадь: бумага в клетку/линейку, вертикальная линия полей с подписью «поля», дырки скоросшивателя в sidebar, васи-лента на форме, штампы «вопрос»/«ответ», скрепка на карте, маркер-выделитель в заголовках, жёсткие смещённые тени (не blur!) как у наклеенной бумаги.

### 4.2 Root Variables (:root)

| Переменная | Значение | Смысл |
|---|---|---|
| `--font` / `--serif` | PT Sans / PT Serif | базовый / акцидентный |
| `--gutter` | 52px | ширина поля тетради |
| `--cell` | 28px | шаг клетки экрана |
| `--t` | 220ms | базовая длительность микроанимаций |
| `--ease` | cubic-bezier(0.22, 1, 0.36, 1) | агрессивный ease-out (UI) |
| `--spring` | cubic-bezier(0.34, 1.3, 0.64, 1) | пружина (окна) |
| `--flip` | cubic-bezier(0.45, 0, 0.25, 1) | мягкий ease-in-out (флип+тень+подъём) |

### 4.3 Palettes (единый источник — `PALETTE_META` в ui.js)

| id | Название | accent | accent-2 | tab | radius | stamp |
|---|---|---|---|---|---|---|
| ember | Охра | `#e85d04` | `#ff8a3d` | `#ffb703` | 14px | solid |
| sea | Синий | `#156d8a` | `#4eb3c9` | `#7ec8d4` | 18px | double |
| moss | Мох | `#4a7a32` | `#8fbf5a` | `#c3d67a` | 12px | dashed |
| berry | Ягода | `#9b2d5c` | `#e06a9a` | `#f0a3c2` | 20px | solid |
| violet | Фиолет | `#6b3fa0` | `#b07def` | `#cbb2ea` | 16px | solid |
| gold | Золото | `#c3922d` | `#e8c25a` | `#f0d37a` | 10px | double |
| crimson | Алый | `#c0392b` | `#ef7a6c` | `#f0a196` | 8px | dashed |
| teal | Бирюза | `#0f7a6c` | `#4ec9b4` | `#8fd9c9` | 20px | solid |
| slate | Графит | `#4d5d73` | `#8aa0b8` | `#b7c4d4` | 14px | solid |
| indigo | Индиго | `#3949ab` | `#7e8ce8` | `#aeb6f0` | 16px | solid |

Каждая палитра также задаёт: `--margin` (=accent), `--on-accent` (#20150b для тёплых светлых ember/gold, #fff8f0 для остальных восьми — по luminance акцента), `--accent-3` (третий поддерживающий тон: flame, конфетти, hover скроллбара, маркер колоды), `--washi-angle/a/b`, `--stamp-style`, `--study-pattern/--study-size/--study-pos` (узор кнопок «Учить»), `--dot-pattern/--dot-size` (узор активных точек/переключателей), уникальный `--menu-pattern*` фона меню.

Точки палитр генерирует `renderThemeDots()` (ui.js) в оба контейнера `.theme-dots`; цвет — inline `style.backgroundColor` (см. Pitfalls №1).

### 4.4 Mode Variables

| Переменная | Light | Dark | Смысл |
|---|---|---|---|
| `--paper` | mix(accent 12%, #f5ecd9) | mix(accent 11%, #12110f) | фон экрана |
| `--side` | mix(accent 30%, #e4ceab) | mix(accent 18%, #1a1714) | обложка/sidebar |
| `--card` | mix(accent 7%, #fffaf2) | mix(accent 14%, #221c18) | карточки, модалки |
| `--ink` / `--muted` | #2c2218 / #5f5144 | #f3ebe0 / #c4b3a2 | текст / вторичный |
| `--line` | #2c2218 | #eadccb | рамки |
| `--on-accent` / `--tab-ink` | — / #2c2218 | — / #16120e | текст на акценте: **пер-палитровый** (см. таблицу палитр), выбирается по luminance акцента; WCAG ≥4.5 на всех 10×2 комбинациях |
| `--danger` / `--known` / `--unknown` | #b42323 / #2c6e43 / #b85a10 | #ff8a7a / #9be08a / #ffb45c | статусы |
| `--shadow` | mix(accent 50%, #3b2416) | #050403 | жёсткие тени |
| `--grid` | mix(accent 26%, transparent) | mix(accent 28%, transparent) | линии ЭКРАНА |
| `--face-grid` | mix(accent 16%, transparent) | mix(accent 18%, transparent) | линии КАРТ (мягче!) |
| `--hole` | radial белый | radial тёмный | дырки скоросшивателя |

### 4.5 Card Shadow Architecture (важно!)

Тень — **жёсткая копия со сдвигом**, живёт на плоских обёртках, НЕ внутри 3D:

| Элемент | Правило |
|---|---|
| `.flashcard-wrap::before` | `top:18 right:0 bottom:0 left:0; background:var(--card-shadow); translate(6px,7px)` — инсеты от **padding-box** (обёртка имеет padding 18/8/12/0), нули справа/снизу дают честный выступ 6/7px за карту |
| `.focus-wrap::before` | то же, но `inset:0` |
| `--card-shadow` | `color-mix(var(--shadow) 82%, transparent)` — тени обёрток мягче системных; кнопки/модалки используют полный `--shadow` |
| Подъём | WAAPI-третья анимация `translateY(0→-6px)` на обёртке (см. Swing) — карта и тень поднимаются как одно целое; по завершении коммитится inline-стиль |
| Swing | **WAAPI-драйвер** (`startFlipAnimation`, study.js): одним тактом создаются 3 анимации — `rotateY` на `.flashcard-inner`, `translate(6,7) scaleX(k)` на `::before` обёртки (хост = фактический родитель карты: `.flashcard-wrap` или `#focus-wrap`), `translateY(-6px)` подъёма на обёртке; общий старт ⇒ нет дрейфа композитора. k семплируется из \|cos(180°·p)\| каждые ~34мс с полом 0.03; по завершении стили коммитятся (класс + inline transform) и анимации отменяются |

**Модель тени при флипе (детерминированная WAAPI-съёмка):**
- Ширина следует |cos(180°·p(--flip)(t))|: отклонение от идеала ≤1.5% по ходу, на «ребре» — намеренный пол k=0.03.
- Световой сдвиг сохраняется всю анимацию: matrix tx=6.0, ty=7.0 в любой фазе.
- Панель и фокус идентичны (одни сэмплы, база выровнена под карту после фикса padding-box).
- Потолок точности: карта из-за perspective:1400px шире идеального |cos| на ≤2.5% в середине — незаметно в движении.
- Реверс бесшовен: повторный клик продолжает с текущего аналитического угла (`flipRun` хранит from/to/t0/dur; скачок ширины 2.7% вместо ~88% у старого CSS-рестарта).
- Swap: `card-swap-shadow 0.42s var(--ease)` на том же `::before` — тень уезжает/приезжает вместе с картой.

### 4.6 Face Lines (линии тетради на карте)

Фон грани — чистый `var(--card)`; узор вынесен на `.face::before` (`inset:0; z-index:-1; pointer-events:none`) — под текстом, над фоном. Во время флипа узор гаснет: `lines-dim 0.62s var(--flip)` (opacity 1 → 0.12 @39% → 1) — убивает мерцание 1px-полос при 3D-повороте.

| Палитра граней | Узор |
|---|---|
| base (ember) | линейка 31/32px |
| sea, indigo | линейка 27/28px |
| berry, violet | точки Ø1px, сетка 14px |
| moss | диагональ 45°, 23/24px |
| gold | двойная линейка 28/29 + 34/35px |
| crimson | линейка 34/35px |
| teal | сетка 19/20px обе оси |
| slate | точки Ø1px, сетка 14px |

### 4.7 Animation Registry

| Имя | Цель | Длительность | Кривая | Триггер |
|---|---|---|---|---|
| flip (rotateY) + shadow scaleX + lift −6px | **WAAPI-драйвер** `startFlipAnimation` (см. 4.5): 0.62s·span/180, кривая `--flip` для inner/lift, linear+сэмплы для тени | 0.09–0.62s | `--flip` / linear | клик по карте (`flipCard`) |
| Wave-2 keyframes (CSS) | rise-left/right, stamp-slap, more-in, dot-hop, badge-shake, row-new-flash, hit-pulse ×2, wrong-flash, check-draw, sticker-pop (+::before хвост), flame-pulse, clip-sway 14с, fb-in, ws-fade, sheen-sweep, filter-pop, count-pop, ripple-go, doodle-sway | 0.14–0.78s | `--ease`/`--spring` | соответствующие действия (см. Feature Logic) |
| `card-swap` | inner X ±18px + fade | 0.42s | `--ease` | `.is-swap` |
| `lines-dim` | `.face::before` opacity | 0.62s | `--flip` | те же гейты, что флип |
| `rise` | .empty/.workspace/.panel | 0.35–0.45s | `--ease` | появление |
| `row-in` | строки карточек | 0.3s | `--ease` | каждый рендер списка |
| `tape-drop`, `marker-in` | лента, маркер | 0.5s / 0.8s | `--ease` | загрузка |
| `bloom-pulse` | `#theme-bloom` | 0.7s | `--ease` | смена темы |
| view-transition | `::view-transition-new(root)` clip-path circle от точки клика | 620ms | `--ease` | `applyAppearance` |

Меню/фокус-фон: многослойные радиальные градиенты + уникальный `--menu-pattern` каждой палитры. Брейкпоинты: 860px (sidebar наверх, дырки скрыты), 480px (мелкие правки). `prefers-reduced-motion`: всё глушится глобально, грани переключаются через `display` вместо 3D.

---

## 5. Data & Storage

### 5.1 localStorage Keys

| Ключ | Значение |
|---|---|
| `flashcards-app-v1` | JSON всего состояния (см. 3.2) |
| `flashcards-mode` | `light` \| `dark` \| `auto` (авто = следование системной схеме) |
| `flashcards-fontsize` | `s` \| `m` \| `l` (масштаб учебных поверхностей 0.9/1/1.1) |
| `flashcards-palette` | один из 10 id |
| `flashcards-onboarded` | `"1"` после тура |
| `flashcards-theme` | LEGACY: миграция в head-скрипте |

### 5.2 Normalization (normalizeState)

Загрузка переживает любой мусор: не-объект → пустое состояние; колоды без имени/dubli id — долой; карточки с битым deckId, пустым вопросом/ответом, дублем id — долой; статусы вне `VALID_STATUSES` → `new`; имена трим до 80; числа клампятся `max(0, floor(n))`; даты срезаются до 10 символов. Повреждённое хранилище = пустой старт без краша (покрыто тестами).

### 5.3 Daily Logic

- `resetTodayIfNeeded()`: дата не совпала → счётчики дня в ноль (history при этом сохраняется).
- Streak: подряд идущие дни с любой активностью, начиная с сегодня (или вчера, если сегодня ещё пусто).
- `recordStudy(deckId, status)` пишет в `history`; `recordSession` аппендит в `sessions` при показе итога.

### 5.4 IndexedDB — изображения карточек

База `flashcards-images` v1, store `images`, ключ = **cardId**, значение = dataURL уже сжатой картинки. JSON-база в localStorage хранит только текст карточек — картинки живут отдельно и в экспорт/импорт JSON/CSV **не входят** (осознанное ограничение, см. Decisions Log). Очистка: удаление карточки (`finishDeleteCard`) и колоды (`deleteDeck`) удаляют соответствующие ключи IDB fire-and-forget; сид тестов делает `indexedDB.deleteDatabase`. Сжатие: `compressImageFile` → максимум 480px по длинной стороне, WebP q0.6 (фолбэк JPEG q0.6, если WebP недоступен).

---

## 6. Feature Logic

| Фича | Где | Суть |
|---|---|---|
| Bulk input | app.js | строки `вопрос = ответ` (`BULK_SEPARATOR="="`), пропуск мусора, feedback «Добавлено N · пропущено M» (выезд слева + SVG-галочка), warn если 0 |
| Font size | ui.js + modal.js + app.js | секция «Размер текста в карточках» S/M/L в настройках (`#fontsize-switch`, `data-size`, кнопки min-width 54px); `html[data-fontsize]` → `--fs-scale` 0.9/1/1.1; масштабируются учебные поверхности: `.face-text` (оба режима), `.quiz-question`, `.quiz-option`, `.card-rows li`; head-скрипт применяет до первого кадра; битое значение → m; сохранение мгновенное; отступы секций настроек: `.setting-label` 18/10, `.form-actions` сверху 22 |
| Wave-2 сценарные | все файлы | скользящий индикатор вкладок (`.tab-indicator`, refreshIndicators); маркер активной колоды (`.deck-marker` слева, accent-3, внутри padding-box); направленные входы панелей (rise-left/right); overshoot флипа 4° на 82% (+ зеркальный бамп в сэмплах тени); штампы «шлёпаются» на ВИДИМОЙ стороне при каждом перевороте (остаточный наклон −2°); вспышка акцентом новой строки (`row-new`); двухфазное удаление: slide-fade 180мс → collapse 140мс → удаление; sheen прогресса квиза на ВСЁМ треке (`.quiz-progress::after`) только при верном ответе; каскад deck-picker 25мс; bulk-feedback выезд с SVG-галочкой; редкое покачивание скрепки (14с); огонёк серии (svg.flame на accent-3, drop-shadow glow, пульс 1.38×); стикер числа дня (хвостик-треугольник + sticker-pop с поворотом −8→3→−2°); красная рамка пустых полей (required снят — кастомная валидация); кроссфейд workspace при смене колоды (prevDeckId); параллакс бумаги `.main` (rAF, ×0.12/0.08) |
| Motion & interactivity | app.js + ui.js + study.js + stats.js | ripple от точки клика на `.btn/.tab` (делегированный pointerdown, span.ripple); лёгкий 3D-tilt карты за мышью (`pointermove` на `#flashcard`, ≤4°/2.5°, сброс на leave); stagger строк списка 30мс×18; pulse подсветки поиска при появлении результатов (MutationObserver → `.pulse-marks`); квиз: wrong-flash вспышка + check-draw галочка (SVG dashoffset) на верном клике; конфетти 70 частиц при 100% итога (`launchConfetti`, WAAPI, слой удаляется через 2.6с); count-up цифр статистики (550мс, cubic-out); каскадный рост дневных баров (45мс шаг); каскад блоков меню (.07s шаг через nth-child); drag-reorder карточек внутри колоды (HTML5 DnD, индикаторы drop-above/below, `moveCardWithinDeck`); анимированные каракули в пустых состояниях; кастомный скроллбар. Всё гасится глобальным reduced-motion |
| Auto theme | ui.js + app.js | кнопка «Авто» в обоих переключателях (`data-mode="auto"`); на `<html>` два атрибута: `data-mode-pref` (выбор пользователя) и `data-mode` (эффективный); `bindAutoTheme()` слушает `matchMedia("(prefers-color-scheme: dark)")` change → при pref=auto перезапускает `applyAppearance` с синтетическим событием из центра экрана (bloom всегда, даже для системного переключения); head-скрипт разрешает auto до первого кадра (без вспышки); guard `applyAppearance` сравнивает и pref, и эффективный режим — иначе системный путь отсекался бы как no-op |
| Search | ui.js + app.js | живой поиск по текущей колоде: подстрока без регистра в вопросе/ответе, поверх фильтра статусов; подсветка `<mark class="search-hit">` с сохранением регистра; очистка крестик/Esc; сброс при смене колоды; пустой результат «По запросу «X» ничего не найдено.» |
| Quiz mode | study.js + app.js | переключатель «Карточки/Квиз» внутри панели «Учить»; старт: длина 5 / 10 / вся колода (`data-qlen`, 0 = все, клампится к размеру колоды); вопрос → 4 варианта (верный + 3 случайных уникальных ответа других карточек, `buildOptions`); авто-проверка: верный зелёный (`is-right`), кликнутый неверный красный (`is-wrong`), остальные приглушены; меты `Квиз · вопрос i из N · верно K` + прогресс-бар `#quiz-fill`; статус/счётчики/history пишутся сразу при ответе; итог — общий summary-оверлей; repeat-режимы квиза: `quiz` (только ошибочные) и `quiz-all` (тот же набор); стрелки ←/→ в квизе игнорируются |
| Quiz fullscreen | study.js + app.js | вход кнопкой ⛶ (`#quiz-focus-btn`) при активном раунде; узел `#quiz-area` переносится в `#focus-wrap`, `#focus-controls` и `#focus-meta` скрываются, тень даёт `#focus-wrap::before`, текст крупнее (`#focus-wrap .quiz-question/options`); выход — ✕ или Esc (в т.ч. документный fallback при фокусе на body), **прогресс раунда сохраняется**; переключать режимы внутри фуллскрина нельзя; summary открывается ПОВЕРХ фуллскрина (динамический `z-index:66` на `#summary-backdrop`, когда открыт любой фокус) — то же поведение и для flip-раунда в фокусе; «В меню»/«Статистика» из summary сначала закрывают активный фокус |
| Filters | ui.js | `state.cardFilter`; точечное обновление бейджа или полный ре-рендер, если строка отфильтрована |
| Deck picker bar | menu.js | процент known от всех карточек колоды |
| Stats day-bars | stats.js | 7 дней, высота = count/max*26px (min 3, пустой 2px) с каскадным ростом 45мс; стикер числа при hover (`data-count` + ::before/::after pop) |
| Sessions sort | stats.js | date desc, затем по индексу вставки desc |
| Tour | menu.js | 4 шага по селекторам `#menu-today`, `#menu-study-btn`, `#menu-cards-btn`, `#menu-theme-dots`; позиционирование с clamp 12px; флаг в localStorage |
| Theme bloom | ui.js | `startViewTransition` + clip-path круг из точки клика + радиальная вспышка; фолбэк при отсутствии API / reduced-motion |
| Keyboard | app.js | ←/→ навигация карточек (только в study, вне модалок/меню), Ctrl+Enter — сохранить карту / применить bulk, стрелки на .tabs переключают вкладки, Esc — каскад закрытия |
| A11y | везде | role=dialog/tablist/tab/tooltip, aria-modal, aria-selected, aria-pressed, aria-live на метах и feedback, focus-trap, видимый focus-visible |
| TTS-озвучка | study.js + index.html | SVG-иконка `.face-speak` (stroke=currentColor → цвет темы, hover → accent) в правом верхнем углу КАЖДОЙ грани карты; клик озвучивает именно эту сторону (`speakFace(side)`), не переворачивая карту (guard в `flipCard` + stopPropagation); `pickRuVoice` ранжирует голоса Google/Natural/Neural выше, rate 0.92 pitch 1.05; речь глушится при смене карточки и новом раунде; у `.face-text` padding-right:34px — многострочный текст не заходит под иконку; едет в фокус-режим вместе с картой |
| Two-sided decks | study.js + menu.js + ui.js | флаг `deck.twoSided`; основной переключатель — чип `#two-sided-btn` («⇄ обе стороны») в панели «Учить» рядом с режимами (is-active/aria-pressed, клик пересобирает раунд: flip → startStudyShuffle, quiz → перезапуск всей колоды); дубль пункта в меню действий колоды. Раунд строится из ЗАПИСЕЙ `id` / `id#rev` (`buildStudyEntries`): реверс показывает ответ на фронте + «· наоборот» в мете; счётчики раунда ключуются записью; итог считает записи; квиз реверса спрашивает ответ вариантами-вопросами; повторы сохраняют структуру |
| Card images | images.js + app.js + ui.js + study.js | форма: «Картинка…» → сжатие → превью 64px (✕ снимает; при редактировании существующая грузится из IDB); сохранение пишет ключ cardId→dataURL. Отображение: `<img id="face-img-front">` на фронте карты (race-guard: токен по id текущей карточки), миниатюры `.row-thumb` 44px в списке; фокус-режим получает картинку бесплатно (карта переносится целиком). Удаление карты/колоды чистит IDB |
| Picker one-click (Q16) | menu.js + style.css | строка пикера = контейнер `.deck-pick-item` (div): клик по основной зоне `.deck-pick-main` сразу открывает колоду («Карточки»); кнопка «⋯» (`.deck-pick-more`, SVG-три точки currentColor) открывает меню действий; появление more-in (выезд справа, spring), hover строки → точки окрашиваются accent'ом и каскадно подпрыгивают (dot-hop ×3 со сдвигом 60мс), active — прижим |
| Quiz digit keys (Q18) | app.js + study.js + style.css | клавиши 1–4 жимают варианты (document-level listener, гейты: quizActive && !quizAnswered && нет открытых оверлеев); на кнопках бейджи-цифры (::before по data-key): покой — акцентная плашка, hover — scale 1.1; верный → ✓ на зелёном known + scale, неверный → ✕ на danger + badge-shake, dim → opacity/scale down || Data import/export | data.js + index.html | Настройки → «Данные»: скачать базу JSON (`v:2`, вся база с history/sessions), CSV (`deck;question;answer;status`, кавычки по RFC-стилю), импорт файла (.json/.csv). Экспорт колоды — пункт «Экспортировать колоду» в действиях колоды (kind:"deck"). Импорт JSON базы/колоды открывает диалог `data-backdrop`: «Слить» (колоды сопоставляются по имени; дубли карт по сигнатуре deck+question+answer пропускаются; повторный импорт идемпотентен) или «Заменить всё» (normalizeState + сброс selected на первую). CSV мержится сразу: 4 колонки → колоды по имени создаются, 3 колонки → в текущую колоду. Ошибки парсинга → warn-toast, краха нет. Все подтверждения через toast (`showToast(msg, ok/warn)` на #storage-alert) |
| Reliability (раунд правок) | все файлы | счётчики дня: **одна карточка — одно событие за раунд** (`statusCounted`, спам «Знаю» и флип+«знаю» не накручивают); сбой `saveState`/`loadState` → баннер `#storage-alert` (6с); кросс-вкладочная синхронизация (storage-event → loadState+render); Esc-каскад документного уровня покрывает ВСЕ оверлеи при фокусе на body; у каждого бэкдропа stopPropagation в Escape-ветке; поиск автоочищается при опустении колоды («воскрешение» поиска); демо-колоды защищены от дублей (`DEMO_KEY`, кнопка «Добавлено ✓» disabled); bulk-hint предупреждает про первый «=»; countUp до 9999; тур перепозиционируется при resize |

---

## 7. Tests

### 7.1 How It Works

Наборы живут **внутри проекта**: `<проект>\tests\cdp-*-test.ps1` (28 наборов, включая perf-бюджеты). Каждый:

1. Запускает свой Chrome с `--remote-debugging-port`, открывает `index.html`. Пути вычисляются от расположения скрипта — проект переносим; параметры `-DebugPort`/`-BrowserExe` позволяют раннеру раздавать порты и браузер.
2. Сеет localStorage через CDP `Page.addScriptToEvaluateOnNewDocument`.
3. Прогоняет сценарий через `Runtime.evaluate`, собирает `{step, ok, detail}`.
4. Печатает `[PASS]/[FAIL]` или JSON + `TOTAL FAILS`.

Единый раннер `tests\run-tests.ps1`: параллельный пул (по умолчанию 5 инстансов → полный прогон ~100с), режимы `-Smoke` (unit+full+quiz+data+tts ≈30с) и полный, `-Browser edge`, `-Filter <имя>`, текстовый лог падений в `tests\results\failures-<дата>.log`, exit code 0/1.

Запуск: `powershell -ExecutionPolicy Bypass -File tests\run-tests.ps1 [-Smoke] [-Parallel N] [-Browser chrome|edge]`
CI: GitHub Actions (`.github/workflows/ci.yml`, windows-latest + setup-chrome): smoke на push в main, полный прогон через Actions → Run workflow (mode=full); лог падений — артефактом job'а.
Перед правкой файл перечитывают и пересохраняют в UTF8 (проблемы кириллицы в PS 5.1):

```powershell
$c = Get-Content -LiteralPath $f -Raw -Encoding UTF8
Set-Content -LiteralPath $f -Value $c -Encoding UTF8
```

Pre-commit: core.hooksPath=.githooks → smoke перед каждым коммитом (пропуск: git commit --no-verify).
Браузеры: Chrome — основная платформа всех проверок; Edge (Chromium) — smoke совместим на 100% тем же харнессом (`-Browser edge`); Firefox — только лёгкая проверка работоспособности (headless-рендер), полноценный CDP у него другой протокол.

### 7.2 Suites (30)

| Скрипт | Область | Проверок | Критичные шаги |
|---|---|---|---|
| `cdp-full-test.ps1` | Сквозняк A: тур, темы, палитры, cover-fit, picker/pop, study-раунд, summary, повторы, статистика, rename/delete/create колод; B: битый storage | ~65 | `no-errors`, `header-updated`, `summary-line*`, `stats-*` |
| `cdp-e2e-test.ps1` | A: CRUD карточек/колод, клавиатура, счётчики флипа, bulk, persist после reload; B: повторная загрузка | 79 | `persisted-*`, `kbd-*`, `bulk-added` |
| `cdp-extra-test.ps1` | A: табы-стрелки, Ctrl+Enter, focus-навигация, bigStudy, popup-путь, tab-trap; B: пустое хранилище | 42 | `tab-trap`, `create-from-empty` |
| `cdp-focus-test.ps1` | Жизненный цикл focus-режима + summary поверх фокуса | 25 | `card-in-focus`, `focus-stays-open`, `summary-over-focus` |
| `cdp-summary-test.ps1` | Математика итога, оба режима повтора, счётчики дня | 22 | `fill100/fill0`, `repeat-*` |
| `cdp-unit-test.ps1` | Чистые функции: даты, uid, shuffle, normalizeState (edges), bulk-parse, streak, pluralDays, roundComplete, badges | 79 | все |
| `cdp-palette-test.ps1` | 10 палитр + уникальность menu-pattern + тёмный паттерн | 15 | `patterns-unique`=10 |
| `cdp-pattern-test.ps1` | Уникальность узоров study/dot/mode-кнопок по палитрам, шрифт, попап | 24 | `dot-patterned`, `*-unique`=10 |
| `cdp-menu-test.ps1` | Cover-fit, сегодня, тур, picker-строки/бары, pop, z-order настроек над меню | 31 | `today`, `settings-z-above` |
| `cdp-filter-test.ps1` | Фильтры, бейджи, удаление внутри фильтра, live-обновление, сброс после reload | 27 | `row-removed-live`, `filter-reset` |
| `cdp-search-test.ps1` | Поиск: живой ввод, регистр, ответ, поверх фильтра, подсветка/multi-match, очистка крестик/Esc, сброс при смене колоды; B: не персистится | 23 | `highlight-mark`, `search-over-filter` |
| `cdp-quiz-test.ps1` | Квиз: вход, длины, 4 уникальных варианта, авто-проверка, счётчики, итог/повторы; фуллскрин: ⛶-вход, скрытая панель, тень, крупный шрифт, бар, сохранение прогресса при ✕/Esc, summary поверх (z=66), retry внутри фуллскрина; B: сброс режима | 46 | `summary-math`, `qfs-progress-saved`, `qfs-summary-over` |
| `cdp-autotheme-test.ps1` | Авто-тема: boot по схеме, 3 кнопки в обоих свитчах, следование эмуляции схемы, bloom-координаты, ручной override держится, возврат авто, персистентность; B: reload при тёмной схеме | 15 | `follows-light`, `manual-holds`, `persist-follows-dark` |
| `cdp-fontsize-test.ps1` | S/M/L: дефолт m, подписи, масштаб строк 16→14.4/17.6 и карт 30→33, активная кнопка, сохранение; B: reload хранит l; C: битое значение → m | 13 | `row-scaled-*`, `face-scaled-up`, `bad-value-fallback-m` |
| `cdp-motion-test.ps1` | Движение: ripple+очистка, stagger 0/30/60, tilt set + edge-hold стабильность (0 срывов, кламп 3.5°, шаг ≤0.4°) + сброс вне карты, pulse поиска (позиция крестика, scale-pop 1.125×2), wrong-flash, check-reveal, конфетти 70 при 100%, count-up 2→4, рост баров, menu-stagger 0.07s, каракули, drag reorder + persist, scrollbar-css | 22 | `M14:tilt-edge-stable`, `M7:confetti-spawn`, `M12b:reordered` |
| `cdp-wave2-test.ps1` | Волна-2: индикаторы табов/колод, направленные панели, overshoot ~4° off-180, stamp-slap на видимой стороне, sheen только верный, field-error, row-new акцент, collapse 200мс, bulk fb+галочка, picker 25мс, flame серии, стикер data-count, crossfade колод, параллакс −19.2px | 19 | `W4:overshoot`, `W5:stamp-slap`, `W15:parallax` |
| `cdp-stats-test.ps1` | Цифры, элементы колод, дневные бары, деталь колоды, рост сессий | 24 | `day-activity`, `sessions-grew` |
| `cdp-reset-test.ps1` | Сброс прогресса: confirm/cancel, изоляция других колод | 18 | `other-deck-intact` |
| `cdp-library-test.ps1` | Библиотека, добавление демо-колод (30/12/15 карт) | 23 | `cards30`, `cards42` |
| `cdp-bulk-test.ps1` | Парсер: пробелы, мусор, пустые, несколько порций, warn | 17 | `parsed`, `no-garbage` |
| `cdp-spacing-test.ps1` | Регрессия отступов: меню, streak, поля модалок | 13 | все |
| `cdp-stats-empty-test.ps1` | Пустая статистика, кнопка «Учить» | 5 | `go-study` |
| `cdp-fixes-test.ps1` | Надёжность: спам-счёт, одно событие/карта, сброс по раундам, countUp 9999, баннер квоты, Esc-каскад на body (bulk/library/stats/menu), автоочистка поиска + видимость новой карты, кросс-вкладка, guard библиотеки, resize тура | 16 | `F1-no-known-spam`, `E-cross-tab-reload` |
| `cdp-tts-test.ps1` | Озвучка: две SVG-иконки на гранях, stroke=currentColor, цвет = --ink (canvas-декодинг), длинный многострочный текст не заходит в зону иконки (Range по строкам), клик иконки не флипает, фронт/тыл озвучиваются, stop, пустой guard, иконки едут в фокус | 14 | `ui-theme-color`, `text-clear-of-icon` |
| `cdp-schema-test.ps1` | Миграции: legacy без v, v:1, будущее v:99 (+постороннее поле) без краша, битый v; saveState пишет v; версионированный reload | 10 | `migrate-future-no-crash`, `reload-versioned-ok` || `cdp-keys-test.ps1` | Q16/Q18: структура строки пикера (main+more), one-click открытие колоды без actions-pop, подсказки data-key, цифра выбирает верный/неверный вариант, игнор после ответа и вне квиза | 8 | `picker-oneclick-open`, `digit-right-picks` || `cdp-perf-test.ps1` | Перфоманс-бюджеты на колоде из 404 карт (медиана замеров): рендер списка, ввод поиска, старт квиза, рендер статистики; регрессия heavy-mode `.no-anim` | 6 | `budget-render-404-le120`, `heavy-mode-active` || `cdp-images-test.ps1` | Картинки: IDB roundtrip/delete, сжатие 1200×900 → ≤480 WebP, превью в форме, сохранение новой карты с ключом по id, миниатюра в списке, картинка на фронте карты (и скрыта для обычной), редактирование: превью из БД + снятие удаляет ключ, deleteCard чистит IDB | 15 | `compress-max-side-480`, `delete-cleans-idb` || `cdp-reverse-test.ps1` | Двусторонние: buildStudyEntries удваивает с #rev, раунд 4 записи, swap сторон + мета «наоборот», завершение после всех записей, итог по записям, квиз реверса, чип на панели (toggle off/on пересобирает раунд 4↔2), синхронность с меню действий, normalizeState хранит twoSided | 19 | `round-complete-after-4`, `chip-toggles-on` || `cdp-data-test.ps1` | Данные: UI-кнопки настроек, форма payload базы и колоды + имя файла, CSV-экспорт (заголовок, строки, round-trip, кавычки с `;` и `""`), CSV-merge с дедупликацией, диалог импорта колоды (merge по имени, идемпотентность), merge чужой базы (twin-mapping, дедуп в twin, новая колода), честный replace маленьким файлом + selected, битый файл → warn без краха, кап sessions=200, Esc data-слоя на body | 25 | `imp-merge-dedupe-in-twin`, `sessions-cap-200` |

### 7.3 Test Rules

- **Даты в сиде — только динамические** (`new Date()` → `YYYY-MM-DD`): приложение сбрасывает суточные счётчики по дате, хардкод «вчера» ломает тест.
- Ассерты не зависят от порядка shuffle (случайность перемешивания легитимна).
- Эталон состояния после прогона: **все 30 наборов зелёные** (эталон ~769 ok / 0 fail; perf-бюджеты: рендер 404 ≤120мс, поиск ≤25мс, квиз ≤5мс, статистика ≤30мс).
- Headless CDP `Emulation.setEmulatedMedia` обновляет ЗНАЧЕНИЕ matchMedia живьём, но НЕ диспатчит событие change — системный путь в тестах эмулируется прямым вызовом `applyAppearance({mode:"auto"})`; на реальных ОС событие нативное.

---

## 8. Decisions Log

| Решение | Почему (why) |
|---|---|
| Аудит-2026-08: батч A «гигиена» | Удалён мёртвый CSS (`.small-count`/`count-pop`, дубль `mark.search-hit`, мёртвый `#focus-wrap .quiz-progress`, избыточный 3-й `.quiz-option`); убрана отладочная запись `flashcards-vt-debug`; BOM срезается при импорте; тур закрывается навсегда при закрытии меню (флаг в `hideTour`); версии всех ассетов синхронизированы (`v=39`) |
| Тень на плоских обёртках, не внутри `.flashcard` | Внутрь `preserve-3d` её начинало **резать** при пересечении плоскостей во время вращения |
| Единая кривая `--flip` (ease-in-out) для флипа, подъёма и гашения линий | Раньше ease-out заканчивал движение рывком в хвосте, а тень «догоняла» раньше карты; симметричная кривая распределяет движение по всем 0.62s — старт, «ребро» (39%) и финиш совпадают |
| Тень качается `linear` по 14 плотным сэмплам, а не easing'ом | Ширина тени = |cos(угла)| — нелинейная функция прогресса; сэмплы сняты с реальной кривой поворота |
| Подъём −6px на обёртке через `:has()` | Карта и тень поднимаются как один объект; на самой карте transition убран как мёртвый |
| Линии грани на `.face::before` + `lines-dim` в движении | 1px-полосы алиасят и мерцают при 3D-повороте; в быстрой фазе их просто нет |
| `--face-grid` (16%/18%) мягче `--grid` (26%/28%) | Одна и та же полупрозрачная линия над более белой картой читается темнее, чем над бежевым экраном — выравнивает восприятие |
| Точки палитр генерирует JS из `PALETTE_META` | Было 20 дублей в HTML + 10 CSS-правил; теперь одна строка на новую палитру |
| Цвет точки — inline `backgroundColor`, не `background` | Шорткат `background` сбрасывает `background-image` и убивает узор активной точки (ловил тест) |
| `shadow-swing-back` удалён | Был байт-в-байт дубликатом `shadow-swing-fwd` |
| `.modal { border-radius: 16px }` литералом | Осознанно: тест `modal-radius` фиксирует 16px независимо от палитры; остальное — через `var(--radius)` |
| Таймер 500ms поверх `animationend` свапа | CSS 420ms; страховка от потерянного события при скрытии вкладки |
| Без модулей/сборки | Работа с `file://` без сервера; CORS-модули там не работают |
| Reduced-motion: грани через `display` | 3D-трансформ отключён глобально, поэтому флип эмулируется показом нужной грани |
| Summary поверх фокуса (z-index 66 динамически) | Итог раунда не должен выгонять из полноэкранного режима: квиз/карта продолжаются после закрытия итога; статический z-index ломал бы stats-over-summary, поэтому поднимается только при открытом фокусе |
| Маршрутизация ✕/Esc фокуса по `quizFullscreen` | Одна кнопка ✕ обслуживает два режима фуллскрина; без маршрутизации выход из квиза вызывал бы `exitFocusMode` и молча ничего не делал |
| showLayer/hideLayer вместо 12 копий add-class+reflow | Оверлей-паттерн дублировался в каждом окне; единые хелперы в modal.js убрали ~50 строк копипасты (регэксп-массаж при внедрении подменял тела хелперов — ловилось полным прогоном) |
| Делегирование событий строк списка на контейнер | Пер-строчные листенеры (click + 4 DnD) на 404 строках = ~2400 подписок на рендер; делегирование в `bindCardRowsDelegation` убирает их и память |
| Heavy-mode списков (>60 строк без row-in) | Массовая вставка 400 анимаций одновременно давала ~70мс на рендер; отключение построчных анимаций на больших партиях убирает пик без потери UX на малых |
| Флаг `--allow-file-access-from-files` удалён из харнесса | Отключение same-origin для file:// — приманка для эвристик Defender; не нужен (нет XHR), побочный эффект (cssRules SecurityError) обойдён computed-style проверками |
| Зона tilt — стабильная обёртка, а не живой rect карты | Наклон сдвигает хит-квадрат карты: замер по нему = петля обратной связи и мерцание у края; обёртка не трансформируется и чуть шире — эффект стабилен вплоть до кромки |
| Правило «одна карточка — одно событие за раунд» (statusCounted) | Повторный клик «Знаю» и флип+«знаю» накручивали дневные счётчики (5 кликов = +5 «изучено»); метрики меню разошлись бы с итогом раунда. Первая отметка карты в раунде фиксирует событие; новые раунды начинают отсчёт заново |
| stopPropagation в Escape-ветке КАЖДОГО бэкдропа | Esc на настройках всплывал в документ, а расширенный каскад closeTopModal закрывал следующий слой (меню) — регрессия поймана зондом; единый инвариант: свой обработчик гасит событие, документный работает только при фокусе на body |
| Кросс-вкладочная синхронизация через storage-event | Две вкладки одного файла молча перетирали данные друг друга (последняя сохранение побеждает); теперь внешнее изменение adopting через loadState+render |
| Импорт колоды сливается в существующую по имени | Повторный импорт того же файла обязан быть идемпотентным: иначе каждая загрузка создаёт дубль колоды с копиями карт; сигнатурная дедупликация (deck+question+answer) добивает остатки |
| CSV — диалект `deck;question;answer;status` | Первый столбец сохраняет структуру колод при полном экспорте; 3-колоночная форма принимается как «в текущую колоду»; кавычки с удвоением покрывают `;` и переводы строк внутри полей |
| Тесты кликают кнопки меню действий по тексту, не по индексу | Меню действий расширилось (экспорт колоды), числовые индексы сдвинулись и сломали сразу несколько наборов — поймано полным прогоном |
| Изображения — IndexedDB вне JSON-базы + сильное сжатие | localStorage (~5МБ) не выдержал бы dataURL; IDB снимает лимит. 480px/WebP q0.6 выбрано пользователем («ещё более сильное сжатие»): фото ~20-60КБ, сотни картинок в запасе; текст вопроса/ответа остаётся крошечным и полностью портируемым через экспорт |
| Hover-цвет точек «⋯»: light = mix(accent 72%, ink), dark = accent-2 | Свип WCAG 10 палитр × 2 темы: базовый accent в тёмных темах даёт 1.9–2.9 на тёмной карте (violet/indigo/slate/berry), светлое золото на креме 2.36; accent-2 в темноте поднимает до 4.3–7.9, подмес чернил в свету — до 3.55+. Замерять арифметикой токенов через probe-resolve: canvas-декодер падает на color()/color-mix, синтетический mouseover не ставит :hover |
| View-transition анимация — CSS-keyframes, не JS `animate()` | JS-вариант (`await ready → animate`) содержал гонку: на занятом основном потоке Chrome успевал запустить дефолтный кроссфейд group-слоя (250мс), наша анимация цеплялась позже и обрывалась его финалом — «анимация доходит до середины и щёлкает до конца» у реальных пользователей. CSS-keyframes подхватываются автоматически при появлении псевдоэлемента — гонки не существует по построению; дефолты group/old заглушены явно |
| Иконка озвучки — inline SVG на грани, не эмодзи на панели | Эмодзи имеет собственную чёрно-белую обводку и не окрашивается темой; SVG со stroke=currentColor наследует `--ink`/accent; размещение на карте устраняет разрыв контекста (действие над картой — на карте) и работает в фокус-режиме бесплатно |
| Реверс через записи `id#rev`, а не дубли карт | Отдельные реверс-карты раздули бы данные и списки; суффикс в studyOrder даёт нулевой оверхед хранилища, а счётчики раунда, итог и повторы автоматически получают честную семантику «позиций раунда» |
| stopPropagation не действует на СОСЕДНИЕ листенеры того же узла | Клик `.face-speak` и flipCard висят на одном #flashcard: погасили всплытие — flipCard всё равно получил событие; нужен guard внутри самого обработчика (`closest('.face-speak')`) |
| Чередующиеся оценки одной карты в тестах | В двустороннем раунде одна карта отмечается несколько раз; «known затем unknown» оставляет статус unknown (последняя запись решает) — тестовые ожидания должны быть детерминированы |
| IDB-ответы приходят позже рендера — нужен race-guard | `showStudyCard` запускает `imgGet` асинхронно; при быстрой навигации ответ устаревшей карточки может прийти последним и «приклеиться» к чужой карте — токен по id текущей карточки сверяется в момент разрешения промиса |
| Картинки не входят в экспорт JSON/CSV | IDB и localStorage — раздельные хранилища; перенос базы с картинками потребовал бы zip/встроивание dataURL в JSON (раздувание файла в десятки МБ). Осознанное ограничение Фазы 2, задокументировано в §5.4 |
| Inline-слушатели + делегирование на одном списке = двойной вызов | При внедрении делегирования inline-хвосты кнопок строк не вычистили — edit/delete срабатывали дважды; E2E не ловит КРАТНОСТЬ вызовов (конечное состояние то же) — при дублировании путей обработки событий проверять количество модалок/вызовов, не только итог |
| Фича без теста «на существование» теряется в рефакторах | Heavy-mode (>60 строк без row-in) был внедрён и потерян при последующих правках: CSS-класс `.no-anim` остался, JS-переключатель исчез; ни один тест не проверял его наличие — внешние аудиты ловят такое мгновенно |
| Псевдоэлементы наследуют CSS-переменные от ПОРОЖДАЮЩЕГО элемента | `::view-transition-new(root)` читает `--bloom-x/y` из `<html>`; установка переменных на `#theme-bloom` (даже с теми же именами) до псевдо не доходит — координаты дублируются на корень |
| Координаты клика для view-transition — ТОЛЬКО в процентах окна | При системном масштабировании (dpr 1.5 у пользователя) пиксельные circle(at Xpx Ypx) рисуются в пространстве растрового снапшота и «стекают» к левому верхнему углу пропорционально удалённости точки; проценты (x/innerWidth*100%) инвариантны к масштабу. Диагностика: маркеры на странице + строка localStorage, телеметрия clip-path через getComputedStyle(html,'::view-transition-new(root)') |\r\n| У view-transition есть ТРИ дефолтные анимации, а не одна | Chrome запускает кроссфейды на `group`, `old` и `new` слоях (250мс); глушить нужно все три (`animation:none`), иначе «щелчок» в середине кастомной анимации; headless-чистый профиль эту гонку НЕ воспроизводит — проверять телеметрией `document.getAnimations()` с фильтром по pseudoElement (element.getAnimations() псевдо не возвращает) |
| Единый WAAPI-драйвер флипа вместо CSS-анимаций | Вращение карты и scaleX тени были двумя независимыми композиторными анимациями с разными механизмами старта (класс vs `:has()`-гейт) — на живом GPU дрейфовали друг относительно друга; общий `element.animate()` в одном такте гарантирует общее время старта, а реверс продолжается с текущего угла без скачка |

---

| Батч B «данные» (аудит-2026-08) | Битый JSON в localStorage бэкапится в -corrupt ключ + warn-toast; merge сессий сортирует по дате перед капом (свежие локальные не вытесняются старыми импортными); при загрузке GC осиротевших картинок IndexedDB (imgGcOrphans) |
## 9. Pitfalls

- `el.style.background = ...` (шорткат) затирает `background-image` → юзать `backgroundColor`.
- `var()` внутри `@keyframes` ненадёжен → в ключевых кадрах тени литералы `translate(6px, 7px)`.
- Сдвиг тени карты задан в ТРЁХ местах синхронно: `.flashcard-wrap::before`, `#focus-wrap::before`, WAAPI-кадры в `startFlipAnimation` (+ отдельная амплитуда в `card-swap-shadow`) — менять только все сразу, иначе флип разойдётся со статикой.
- Любой `transform` на предке создаёт 3d-context: тень внутри начнёт резаться — держать её на плоских обёртках.
- Класс `was-flipped` снимается только при смене карточки — он нужен гейтам обратной анимации; не «чистить» его лишний раз.
- После правок CSS поднимать `?v=N` у `<link>` в index.html — иначе кэш браузера покажет старое.
- Сиды тестов — с динамической датой (суточный сброс).
- `void el.offsetWidth` перед добавлением анимационного класса обязателен (рестарт анимации).
- Функции глобальные — новые имена проверять на коллизии по всем 8 файлам.
- `crypto.randomUUID` может отсутствовать — есть фолбэк `uid()`.
- Esc фокуса: слушатели на бэкдропе + документный fallback в app.js — иначе Esc «мёртв», когда activeElement = body (клик по пустому месту).
- `beginQuiz` валидирует id по текущей колоде и падает к полному набору — иначе удаление карточек при открытом итоге даёт мягкую блокировку раунда.
- Инлайн-стили/классы-состояния квиза не должны позволять листу (`#quiz-area`) быть уже обёртки фокуса — тень `::before` рассчитана на точное совпадение (тест `qfs-sheet-fills`).
- Инсеты абсолютных псевдоэлементов отсчитываются от **padding-box**, а не границы: у обёртки с паддингом значения «на глаз» дают двойное вычитание (тень исчезала за картой). Проверено геометрическим аудитом `cdp-design-audit.ps1` (выступ 8/10px во всех состояниях).
- Абсолютные маркеры внутри контейнеров с `overflow:auto` (например `.deck-list`) обрезаются при отрицательных left — держать их в пределах padding-box и увеличивать padding-left контейнера.
- Контраст: светлый `--on-accent` и `--muted` подобраны под WCAG ≥4.5 на всех 10 палитрах — при смене палитр прогонять контрастную часть `cdp-design-audit.ps1`.
- Композиторные анимации отдают устаревшие `getComputedStyle`/gBCR на лету — для съёма геометрии в полёте использовать `getAnimations()` + `pause()` + принудительный reflow (`void el.offsetWidth`).
- Угол флипа «откуда» фиксируется ДО переключения `state.flipped` (в `flipCard` передаётся `!state.flipped`) — иначе `currentAngle()` на холостом старте даёт вырожденный диапазон 180→180.
- **Tilt по gBCR живого элемента = петля обратной связи**: наклон меняет проекцию rect → следующий замер усиливает угол (срыв у краёв). Кэшировать прямоугольник до наклона (pointerenter), клампить углы, события держать на документе с фильтром closest — иначе pointerleave от поворота дёргает эффект.
- Замер контраста «на лету»: `.main` и др. имеют transition background-color 0.4s — при свипе палитр/тем отключать переходы (`*{transition:none!important}`) или ждать ≥400мс, иначе сэмплируется промежуточный цвет.
- `--on-accent` пер-палитровый: тёмный текст (#20150b) только на светлых тёплых акцентах (ember, gold); на остальных восьми — светлый (#fff8f0). Один токен на все палитры физически не проходит WCAG 4.5.
- Chrome может сериализовать color-mix как oklab — для парсинга вычисленных цветов в тестах используйте canvas-декодинг (fillStyle + getImageData).
- Без флага `--allow-file-access-from-files` (убран из харнесса как рискованный) file://-стили кросс-доменны: `sheet.cssRules` кидает SecurityError — поведенческие проверки стилей делать через computed-style (например `scrollbar-width: thin`), а не перебор правил.
- Массовые замены регэкспом по коду делай ДО вставки новых хелперов, иначе заменитель подменяет тела свежих хелперов их вызовами (рекурсия → краш загрузки; ловилось полным прогоном).
- Бейслайн производительности: рендер 404 строк ≈70мс (чистое создание DOM — не оптимизировать дальше без виртуализации), ввод поиска ≤10мс; партии >60 строк — heavy-mode без row-in (#card-rows.no-anim).
- Тесты поднимают Chrome с `--remote-debugging-port` — эвристики Defender могут предупреждать; это ожидаемо, профиль изолирован во временной папке, процесс гасится в finally.
- Блок `.btn, .tab { position:relative }` стоит в конце стилей и перебивает одиночные класс-селекторы позиционирования с равной специфичностью — абсолютные элементы внутри кнопок (например `.search-clear`) требуют контекстный селектор (`.search-box .search-clear`).
- Пульс подсветки поиска: анимация 0.55s×2 = 1.1s; таймаут снятия класса `.pulse-marks` в app.js должен быть ≥ длительности, иначе анимация обрезается.
| ?v= нужен на ВСЕХ ассетах, не только CSS | Кэшировался старый ui.js под новым style.css: координаты писались не на <html>, круг шёл из фолбэка 50%/50% («всегда из той же точки»). Лечение: версионировать каждый <script src> + детектор — head-скрипт хранит __ASSET_V, app.js ставит __RUNTIME_V; расхождение через секунду после load показывает toast «Ctrl+F5» (старый код сам себя поймать не может) |
- У `Map` нет метода `.add` (только `.set`) — опечатка внутри click-обработчика даёт неперехваченное исключение, которое в тестах выглядит как `Script error.` в `__errs`, а не как падение сценария.
- Тесты, кликающие кнопки меню действий колоды, не должны использовать числовые индексы (`[3]`) — состав меню меняется; искать по `textContent.includes("...")`.

---

## 10. Product Principles

Выжимка из продуктового исследования (исходник удалён, принципы канонизированы здесь):

1. **Active recall прежде всего**: переворот — момент вспоминания; сначала думает, потом видит ответ.
2. **Скорость создания**: карточка ≤ 10 секунд; массовый ввод «вопрос = ответ» построчно.
3. **Два разделённых режима**: «Карточки» (создание) и «Учить» (изучение); focus-режим — один объект на экране.
4. **Самооценка после ответа**: «Знаю / Не знаю», результат сразу в статистику.
5. **Видимый прогресс**: счётчик сегодня, серия дней, проценты колод, 7-дневные мини-графики, лог сессий.
6. **Мгновенный старт**: библиотека готовых колод — учиться можно без создания своего.
7. **Офлайн-first**: всё в localStorage, работает без сети и сервера.
8. **Доступность**: тёмная тема, focus-trap, aria-атрибуты, reduced-motion, крупные зоны нажатия.
9. **Мотивация серией**: streak показывается от 2 дней подряд.

---

## 11. Roadmap Priorities

Приоритеты следующих итераций (в порядке значимости):

1. ~~Поиск по карточкам~~ — **готово** (живой поиск с подсветкой, см. Feature Logic).
2. ~~Квиз-режим~~ — **готово** (выбор из 4, авто-проверка, длины 5/10/все, повтор ошибок).
3. ~~Авто-тема~~ — **готово** (кнопка «Авто», matchMedia-слушатель, bloom при системном переключении).
4. ~~Размеры шрифта S/M/L~~ — **готово** (масштаб 0.9/1/1.1 учебных поверхностей, ключ `flashcards-fontsize`).
5. ~~Экспорт/импорт~~ — готово (JSON+CSV, слить/заменить, кап sessions).`r`n6. ~~TTS-озвучка~~ — готово (SVG-иконки на гранях).`r`n7. ~~Двусторонние колоды~~ — готово (записи #rev, чип на панели Учить).`r`n8. ~~Изображения~~ — готово (IndexedDB, 480px WebP q0.6, фронт-грань + миниатюры).`r`n9. ~~Единый раннер~~ — готово (`run-all.ps1`: таблица, тайминги, exit code).
10. Дорожная карта из опроса закрыта полностью.

---

## 12. Conventions

Как есть в проекте (не жёсткие запреты, а сложившийся стиль — следуй ему):

- Vanilla ES2020+: `const/let`, стрелки, шаблонные строки, деструктуризация; без TS, без JSDoc-типов.
- Комментарии в коде практически отсутствуют (единственное исключение — пояснение в head-скрипте index.html); самодокументирующие имена.
- ID и CSS-классы — kebab-case; функции и переменные — camelCase; глобальные функции без префиксов.
- Строки UI — русский, прямо в коде.
- CSS: секции с баннерами `/* ==== Имя ==== */`, переменные тем в блоках `html[data-mode]` / `html[data-palette]`.
- Новые списки рендерить через `DocumentFragment`; точечные обновления предпочитать полному `render()`.
- Любое изменение стилей сопровождается подъёмом `?v=N` и прогоном затронутых тестов; структурные изменения — прогоном всех 23.




























