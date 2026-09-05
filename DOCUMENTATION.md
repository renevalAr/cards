# Flashcards — Project Documentation

> Полный контекст проекта для человека или AI. Прочитай этот файл — и можно работать над любой частью без дополнительного изучения кода.
> Стиль: машинно-ориентированный (таблицы, ID, селекторы). Текст RU, заголовки EN.

---

## Table of Contents

1. [Overview](#1-overview)
2. [File Structure](#2-file-structure)
3. [Architecture](#3-architecture)
4. [Design System](#4-design-system)
5. [Data & Storage](#5-data--storage)
6. [Feature Logic](#6-feature-logic)
7. [Backend API](#7-backend-api)
8. [Infrastructure](#8-infrastructure)
9. [Tests](#9-tests)
10. [Decisions Log](#10-decisions-log)
11. [Pitfalls](#11-pitfalls)
12. [Product Principles](#12-product-principles)
13. [Roadmap Priorities](#13-roadmap-priorities)
14. [Conventions](#14-conventions)

---

## 1. Overview

Приложение-флэшкарточки «Карточки» в эстетике школьной тетради (бумага, поля, дырки от скоросшивателя, васи-лента, штампы).

| Свойство | Значение |
|---|---|
| Стек | **Backend:** Python 3.12 + FastAPI + SQLAlchemy + PostgreSQL 16. **Frontend:** Vanilla HTML/CSS/JS (без фреймворков/сборки) |
| Запуск | Docker Compose (`docker-compose up -d`) или `file://index.html` (офлайн-режим) |
| Данные | **Основной:** PostgreSQL через REST API. **Локальный:** localStorage (офлайн-режим или миграция) |
| Аутентификация | JWT (access 15мин + refresh 30 дней) через httpOnly cookies |
| Шрифты | PT Sans + PT Serif с Google Fonts (`display=swap`), фолбэки Segoe UI / Georgia |
| Язык UI | Русский (строки захардкожены в JS/HTML) |
| Палитры | 10, темы светлая/тёмная, выбор сохраняется |
| Тесты | 31 PowerShell CDP-скриптов (smoke), 44 pytest backend tests, 10 Playwright E2E |

---

## 2. File Structure

### Backend (`backend/`)

| Файл | Роль |
|---|---|
| `app/main.py` | FastAPI application, middleware, routers registration |
| `app/config.py` | Settings via pydantic-settings (env vars) |
| `app/database.py` | SQLAlchemy sync engine (psycopg2) + session |
| `app/dependencies.py` | `get_current_user` (JWT verification) |
| `app/middleware.py` | Rate limiting, request logging |
| `app/logging_config.py` | Structured JSON logging |
| `app/models/__init__.py` | User, Deck, Card, RefreshToken, StudySession |
| `app/schemas/__init__.py` | Pydantic schemas for API validation |
| `app/schemas/migration.py` | Migration payload schemas |
| `app/routers/auth.py` | Register, login, /me |
| `app/routers/decks.py` | Deck CRUD + card pagination + FTS search |
| `app/routers/cards.py` | Card CRUD + image upload |
| `app/routers/share.py` | Public deck access by slug |
| `app/routers/study.py` | Study sessions + stats |
| `app/routers/migrate.py` | Data migration from local storage |
| `app/services/auth.py` | bcrypt + JWT utilities |
| `app/services/image.py` | Pillow compression + file management |
| `app/services/share.py` | Share slug generation |
| `alembic/` | Database migrations |
| `tests/` | pytest test suite |

### Frontend (`frontend/`)

| Файл | Строк | Роль |
|---|---|---|
| `index.html` | 529 | Вся разметка + auth UI + inline theme script |
| `style.css` | 2733 | Все стили + auth styles |
| `js/api.js` | 200 | API client + Auth module + Decks module + Data module |
| `js/share.js` | 50 | Public deck viewing + share link copying |
| `js/app-data.js` | 79 | Server sync layer (syncFromServer, CRUD wrappers) |
| `js/router.js` | 57 | Hash-based routing (init, navigate, _handleRoute) |
| `storage.js` | 293 | Local state + localStorage persistence (offline mode) |
| `modal.js` | 180 | Generic modal, focus-trap, overlay pattern |
| `ui.js` | 454 | Palettes, rendering, search, appearance |
| `study.js` | 644 | Flip, quiz, focus mode, round lifecycle |
| `menu.js` | 356 | Main menu, deck picker, tour |
| `stats.js` | 186 | Statistics window |
| `library.js` | 169 | Demo decks |
| `data.js` | 344 | Import/export (JSON+CSV) |
| `images.js` | 84 | IndexedDB image storage + compression |
| `app.js` | 760 | CRUD, bulk input, initialization, auth handlers |

### Infrastructure

| Файл | Роль |
|---|---|
| `docker-compose.yml` | Nginx + FastAPI + PostgreSQL |
| `nginx/nginx.conf` | Reverse proxy, rate limiting, CSP, SSL-ready |
| `backend/Dockerfile` | Python 3.12 + uvicorn + healthcheck |
| `.github/workflows/ci.yml` | CI: backend tests + E2E |
| `.github/workflows/deploy.yml` | CD: build + deploy to VPS |

**Порядок загрузки скриптов** (все перед `</body>`):
```
js/api.js → js/app-data.js →
js/share.js → js/router.js → storage.js → modal.js → ui.js →
study.js → menu.js → stats.js → library.js → data.js →
images.js → app.js
```

---

## 3. Architecture

### 3.1 System Overview

```
┌──────────────────────────────────────────────────────────────┐
│                        Nginx (80/443)                        │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────────┐   │
│  │ /static/*    │  │ /api/*       │  │ /                │   │
│  │ статика      │  │ FastAPI      │  │ SPA index.html   │   │
│  └──────────────┘  └──────┬───────┘  └──────────────────┘   │
└───────────────────────────┼──────────────────────────────────┘
                            │
                   ┌────────▼────────┐
                   │   FastAPI       │
                   │   (uvicorn)     │
                   └────────┬────────┘
                            │
               ┌─────────────┼─────────────┐
               │             │             │
        ┌──────▼──────┐      │      ┌──────▼──────┐
        │ PostgreSQL  │      │      │ Local FS    │
        │ + FTS       │      │      │ (images)    │
        └─────────────┘      │      └─────────────┘
                             │
                      ┌──────▼──────┐
                      │ psycopg2    │
                      │ (sync)      │
                      └─────────────┘
```

### 3.2 Communication Model

**Backend:**
- REST API with JSON responses
- JWT authentication via httpOnly cookies
- Sync SQLAlchemy with PostgreSQL (psycopg2)
- Rate limiting: 5 req/min for auth, 30 req/s for API

**Frontend:**
- All functions are **global**, called directly between files (no modules by design)
- API client (`js/api.js`) with automatic token refresh on 401
- Data layer (`Data` object in `js/api.js`) abstracts API calls
- Offline mode: falls back to localStorage if API unavailable

### 3.3 Global State (storage.js)

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

### 3.4 DOM Contract — все ID

| Область | ID | Назначение |
|---|---|---|
| Auth | `auth-backdrop`, `auth-tab-login`, `auth-tab-register`, `auth-login-form`, `auth-register-form`, `auth-login-error`, `auth-register-error`, `auth-bar`, `auth-user-email`, `auth-logout-btn` | Формы входа/регистрации, бар пользователя |
| Sidebar | `new-deck-btn`, `deck-list`, `settings-btn` | создание колоды, список, настройки |
| Empty | `empty-state`, `empty-new-deck-btn`, `empty-menu-btn` | экран «Пока пусто» |
| Workspace | `workspace`, `deck-kicker`, `deck-title`, `stats`, `workspace-login-btn`, `menu-back-btn`, `share-deck-btn`, `rename-deck-btn`, `delete-deck-btn` | шапка колоды |
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
| Effects | `theme-bloom`, `storage-alert` | вспышка при смене темы; несущий баннер сбоя сохранения (`role=alert`, авто-скрытие 4.5с ok / 8с warn) |

Итого 165+ ID — полный список совпадает с разметкой.

Ключевые классы-состояния: `.hidden` (display:none!important), `.is-open` (бэкдропы), `.is-active` (вкладки/фильтры/точки/колоды), `.is-flipped` / `.was-flipped` / `.is-swap` (карта), `.modal-open` (body, блокировка скролла), `.warn` (bulk-feedback), `.tour-highlight`.

### 3.5 Overlay Pattern (единый для всех окон)

```
.modal-backdrop { opacity:0; visibility:hidden; pointer-events:none;
                  transition: opacity .28s var(--ease), visibility 0s linear .28s }
.is-open        { opacity:1; visibility:visible; pointer-events:auto }
```

Открытие всегда через `showLayer(backdrop)` (= classList.add + reflow), затем `lockScroll(true)` и focus(). Закрытие — `hideLayer(backdrop)`.
Закрытие: снять класс, `lockScroll(false)`, вернуть фокус на триггер (`canFocus(el)` проверяет подключённость и видимость).

Z-index шкала: `menu-backdrop` 40 · `modal-backdrop` 40 · `data-backdrop` 47 · `stats-backdrop` 45 · `settings-backdrop` 46 · `focus-backdrop` 60 · `tour-tip` 70 · `theme-bloom` 300 · `storage-alert` 310. Тайминги появления: модалки и focus — 0.28s, меню и статистика — 0.3s.

Escape: у каждого бэкдропа свой keydown со `stopPropagation()`; плюс документный fallback `closeTopModal()` (input-модалка → настройки). Tab внутри окна — `trapTabKey(backdrop, event)` по списку `getFocusable()`.

### 3.6 Focus Mode (study.js)

Узел `#flashcard` **физически перемещается** `appendChild` между `.flashcard-wrap` (дом) и `#focus-wrap` (полноэкран). Выход возвращает в первый `.flashcard-wrap` внутри `#study-board`. Кнопки дублированы (`mark-*` / `focus-*`), `aria-pressed` синхронизируется в `syncPressState(card)`.

### 3.7 Round Lifecycle

```
startStudyShuffle() → beginRound(shuffle(ids))  // studyOrder, счётчики reset
  ↳ flipCard(): первый флип карточки за раунд → status="unknown",
    today.unknown++, history[deck][today]++, scoredStatus/sessionMarked.add(id)
  ↳ markStatus("known"|"unknown"): sessionMarked.add(id), today/history,
    при известном scoredStatus двойной счёт unknown не идёт
  ↳ moveStudy(±1): индекс по модулю; next на последней при полном раунде → summary
isRoundComplete(): sessionMarked.size >= studyOrder.length
showSummary(): exitFocusMode → запись session → окно итога
repeatStudy(): dataset.mode="unknown"|"all" → beginRound(отфильтрованные id)
```

Смена карточки: класс `is-swap` снимается по `animationend` ИЛИ таймеру 500ms (страховка, CSS 420ms); `swapCleanup` против гонок при быстрых кликах.

### 3.8 Global Function Map

| Файл | Функции |
|---|---|
| storage.js | `dateKey`, `todayDateKey`, `resetTodayIfNeeded`, `getTodayStats`, `uid`, `isPlainObject`, `migrateSchema`, `normalizeHistory`, `normalizeSessions`, `normalizeState`, `showToast`, `showStorageAlert`, `loadState`, `saveState`, `selectedDeck`, `cardsInDeck`, `recordStudy`, `recordSession`, `getDeckHistory`, `getAllTimeStats`, `computeStreak`, `isQuotaError` |
| modal.js | `getFocusable`, `lockScroll`, `trapTabKey`, `showLayer`, `hideLayer`, `openModal` (→ Promise), `canFocus`, `closeModal`, `openSettingsModal`, `closeSettingsModal`, `closeTopModal`, `bindModalEvents` |
| ui.js | `renderThemeDots`, `makeEl`, `badgeFor`, `cardMatchesFilter`, `filterLabel`, `searchMatches`, `appendHighlighted`, `clearCardSearch`, `clearDropIndicators`, `moveCardWithinDeck`, `bindCardRowsDelegation`, `renderDeckList`, `renderCardFilters`, `renderCardRows`, `updateCardRowStatus`, `renderStats`, `resetCardForm`, `render`, `systemDark`, `modePref`, `effectiveMode`, `palettePref`, `fontSizePref`, `applyFontSize`, `syncFontButtons`, `bindAutoTheme`, `syncAppearanceButtons`, `applyAppearance` |
| study.js | `bezProgress`, `currentAngle`, `flipHost`, `clearLift`, `killFlipAnims`, `startFlipAnimation`, `shuffle`, `reduceMotion`, `entryId`, `entryRev`, `buildStudyEntries`, `beginRound`, `startStudyShuffle`, `resetStudy`, `setStudyMode`, `syncTwoSidedBtn`, `toggleTwoSided`, `syncStudyView`, `enterQuizFocus`, `exitQuizFocus`, `enterFocusMode`, `exitFocusMode`, `currentStudyCards`, `setTab`, `syncPressState`, `showStudyCard`, `flipCard`, `isRoundComplete`, `moveStudy`, `markStatus`, `pickRuVoice`, `speakText`, `speakFace`, `stopSpeech`, `updateQuizMeta`, `buildOptions`, `renderQuizQuestion`, `answerQuiz` (check-draw), `nextQuiz`, `startQuiz`, `beginQuiz`, `finishQuiz`, `launchConfetti`, `openSummaryOverlay`, `showSummary`, `closeSummary`, `repeatStudy` |
| menu.js | `pluralDays`, `renderMenu`, `openMenu`, `closeMenu`, `closeAllMenus`, `openMenuPop`, `closeMenuPop`, `renderDeckPicker`, `openDeckPicker`, `closeDeckPicker`, `openDeckActions`, `menuStudy`, `menuOpenCards`, `bigStudy`, `openFirstDeck`, `showTour`, `renderTourStep`, `positionTourTip`, `nextTourStep`, `finishTour`, `hideTour`, `bindMenuEvents` |
| stats.js | `lastDays`, `countUp`, `openStats`, `closeStats`, `renderDayBars` (каскад), `renderStatsWindow` (count-up), `openDeckStats`, `closeDeckStats`, `bindStatsEvents` |
| library.js | `addedDemoIds`, `markDemoAdded`, `renderLibrary`, `openLibrary`, `closeLibrary`, `addDemoDeck` |
| images.js | imgOpen, imgTx, imgReq, imgGet, imgPut, imgDelete, imgGcOrphans, loadImageElement, compressImageFile (IndexedDB + сжатие) |
| data.js | `todayStamp`, `slugifyName`, `downloadBlob`, `buildBackupPayload`, `exportBaseJson`, `exportDeckJson`, `csvField`, `csvSplitLine`, `exportBaseCsv`, `looksLikeCsv`, `parseImportJson`, `parseImportCsv`, `openDataDialog`, `closeDataDialog`, `summarizeImport`, `handleImportText`, `applyCsvImport`, `applyImport`, `bindDataEvents` |
| app.js | `startEditCard`, `showImagePreview`, `resetImageDraft`, `handleImageFile`, `splitBulkPair`, `parseBulkLines`, `openBulkInput`, `closeBulkInput`, `applyBulkInput`, `createDeck`, `renameDeck`, `deleteDeck`, `resetDeckProgress`, `deleteCard`, `saveCard`, `finishDeleteCard`, `bindEvents`, `bindMotionExtras`, `verifyStylesFresh`, `bindAuthEvents`, `showAuthModal`, `hideAuthModal`, `showAuthBar` |
| js/api.js | `API.request`, `API._tryRefresh`, `Auth.init/login/register/logout`, `Decks.list/get/create/update/delete/getCards/addCard`, `Data.deleteCard/enableShare/disableShare/getPublicDeck/getPublicCards/migrateData/exportLocalData` |
| js/share.js | `Share.viewPublicDeck/enableSharing/disableSharing/getShareUrl/copyShareLink/_renderPublicDeck` |
| js/router.js | `Router.init/_handleRoute/navigate/getCurrentRoute/getCurrentParams` |
| js/app-data.js | `AppData.syncFromServer/createDeck/deleteDeck/addCard/deleteCard/isSyncing/getError` |

### 3.9 Constants

| Константа | Значение | Где |
|---|---|---|
| `STORAGE_KEY` / `MODE_KEY` / `PALETTE_KEY` / `ONBOARD_KEY` / `FONT_KEY` | `flashcards-app-v1` / `flashcards-mode` / `flashcards-palette` / `flashcards-onboarded` / `flashcards-fontsize` | storage.js |
| `DEMO_KEY` | `flashcards-demos` (массив id добавленных демо-колод) | library.js |
| `VALID_STATUSES` | Set(`new`, `known`, `unknown`) | storage.js |
| `MAX_NAME_LENGTH` | 80 | storage.js |
| `MAX_SESSIONS` | 200 | storage.js + data.js: кап сессий, при merge сортировка по дате перед усечением |
| `CORRUPT_KEY` | `flashcards-app-v1-corrupt` — бэкап непарсящегося payload | storage.js |
| `BULK_SEPARATOR` | `"="` | app.js |
| `SCHEMA_VERSION` | `1` — поле `v` в payload базы | storage.js |
| `EXPORT_VERSION` / cap sessions | `2` / последние 200 записей | data.js / storage.js |
| `SWAP_DURATION` | 500 (ms, JS-страховка; CSS-анимация 420) | study.js |
| `FLIP_BEZIER` / `FLIP_DUR` | `[0.45, 0, 0.25, 1]` / 620 (ms) | study.js |
| `DEMO_DECKS` | 3 демо-колоды: английский 30 карт, столицы 12, элементы 16 | library.js |
| `ACCESS_TOKEN_EXPIRE_MINUTES` | 15 | backend/app/config.py |
| `REFRESH_TOKEN_EXPIRE_DAYS` | 30 | backend/app/config.py |
| `MAX_IMAGE_SIZE` | 2MB | backend/app/services/image.py |
| `MAX_DIMENSION` | 480px | backend/app/services/image.py |

Модульные переменные-состояния: `swapCleanup`, `scoredStatus`, `sessionMarked`, `focusMode`, `focusTrigger`, `quizActive`, `quizAnswered`, `quizOrder`, `quizIndex`, `quizRight`, `quizWrong`, `quizRetry`, `quizFullscreen`, `flipAnims`, `flipRun` (study.js); `menuPopTrigger`, `tourStep`, `tourSteps` (menu.js); `modalResolver`, `modalTrigger`, `settingsTrigger` (modal.js); `libraryTrigger` (library.js); `bulkTrigger`, `dragCardId`, `rowsBound`, `hadMarks`, `pendingImage`, `editImageId` (app.js); `prevDeckId` (ui.js). Константы анимации флипа: `FLIP_BEZIER=[0.45,0,0.25,1]`, `FLIP_DUR=620`.

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
- Реверс бесшовен: повторный клик продолжается с текущего аналитического угла (`flipRun` хранит from/to/t0/dur; скачок ширины 2.7% вместо ~88% у старого CSS-рестарта).
- Swap: `card-swap-shadow 0.42s var(--ease)` на том же `::before` — тень уезжает/приезжает вместе с картой.

### 4.6 Face Lines (линии тетради на карте)

Фон грани — чистый `var(--card)`; узор вынесен на `.face::before` (`inset:0; z-index:-1; pointer-events:none`) — под текстом, над фоном. Во время флипа узор гасится: `lines-dim 0.62s var(--flip)` (opacity 1 → 0.12 @39% → 1) — убивает мерцание 1px-полос при 3D-повороте.

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

### 5.1 Dual Storage Model

**Primary (online):** PostgreSQL via REST API. All user data, decks, cards, study sessions stored server-side.

**Local (offline/migration):** localStorage for offline mode. Can be migrated to server via `/api/migrate` endpoint.

### 5.2 Database Schema (PostgreSQL)

```sql
users (id UUID PK, email UNIQUE, password_hash, display_name, is_active, is_verified, created_at, updated_at)
decks (id UUID PK, owner_id FK→users, name, description, is_public, share_slug UNIQUE, two_sided, search_vector TSVECTOR, created_at, updated_at)
cards (id UUID PK, deck_id FK→decks, question, answer, status, image_path, position, search_vector TSVECTOR, created_at, updated_at)
refresh_tokens (id UUID PK, user_id FK→users, token_hash, expires_at, is_revoked, created_at)
study_sessions (id UUID PK, user_id FK→users, deck_id FK→decks, known_count, unknown_count, studied_at DATE, created_at)
```

FTS indexes: `decks.search_vector` (GIN), `cards.search_vector` (GIN) — Russian language search.

### 5.3 localStorage Keys

| Ключ | Значение |
|---|---|
| `flashcards-app-v1` | JSON всего состояния (см. 3.3) |
| `flashcards-mode` | `light` \| `dark` \| `auto` (авто = следование системной схеме) |
| `flashcards-fontsize` | `s` \| `m` \| `l` (масштаб учебных поверхностей 0.9/1/1.1) |
| `flashcards-palette` | один из 10 id |
| `flashcards-onboarded` | `"1"` после тура |
| `flashcards-theme` | LEGACY: миграция в head-скрипте |

### 5.4 Normalization (normalizeState)

Загрузка переживает любой мусор: не-объект → пустое состояние; колоды без имени/dubli id — долой; карточки с битым deckId, пустым вопросом/ответом, дублем id — долой; статусы вне `VALID_STATUSES` → `new`; имена трим до 80; числа клампятся `max(0, floor(n))`; даты срезаются до 10 символов. Повреждённое хранилище = пустой старт без краша (покрыто тестами).

### 5.5 Daily Logic

- `resetTodayIfNeeded()`: дата не совпала → счётчики дня в ноль (history при этом сохраняется).
- Streak: подряд идущие дни с любой активностью, начиная с сегодня (или вчера, если сегодня ещё пусто).
- `recordStudy(deckId, status)` пишет в `history`; `recordSession` аппендит в `sessions` при показе итога.

### 5.6 IndexedDB — изображения карточек

База `flashcards-images` v1, store `images`, ключ = **cardId**, значение = dataURL уже сжатой картинки. JSON-база в localStorage хранит только текст карточек — картинки живут отдельно и в экспорт/импорт JSON/CSV **не входят** (осознанное ограничение, см. Decisions Log). Очистка: удаление карточки (`finishDeleteCard`) и колоды (`deleteDeck`) удаляют соответствующие ключи IDB fire-and-forget; сид тестов делает `indexedDB.deleteDatabase`. Сжатие: `compressImageFile` → максимум 480px по длинной стороне, WebP q0.6 (фолбэк JPEG q0.6, если WebP недоступен).

### 5.7 API Client (js/api.js)

- Automatic token refresh on 401 responses
- httpOnly cookies for JWT storage
- `credentials: "include"` for all requests
- Error handling with toast notifications

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
| Quiz digit keys (Q18) | app.js + study.js + style.css | клавиши 1–4 жимают варианты (document-level listener, гейты: quizActive && !quizAnswered && нет открытых оверлеев); на кнопках бейджи-цифры (::before по data-key): покой — акцентная плашка, hover — scale 1.1; верный → ✓ на зелёном known + scale, неверный → ✕ на danger + badge-shake, dim → opacity/scale down |
| Data import/export | data.js + index.html | Настройки → «Данные»: скачать базу JSON (`v:2`, вся база с history/sessions), CSV (`deck;question;answer;status`, кавычки по RFC-стилю), импорт файла (.json/.csv). Экспорт колоды — пункт «Экспортировать колоду» в действиях колоды (kind:"deck"). Импорт JSON базы/колоды открывает диалог `data-backdrop`: «Слить» (колоды сопоставляются по имени; дубли карт по сигнатуре deck+question+answer пропускаются; повторный импорт идемпотентен) или «Заменить всё» (normalizeState + сброс selected на первую). CSV мержится сразу: 4 колонки → колоды по имени создаются, 3 колонки → в текущую колоду. Ошибки парсинга → warn-toast, краха нет. Все подтверждения через toast (`showToast(msg, ok/warn)` на #storage-alert) |
| Reliability (раунд правок) | все файлы | счётчики дня: **одна карточка — одно событие за раунд** (`scoredStatus` Map в study.js, спам «Знаю» и флип+«знаю» не накручивают); сбой `saveState`/`loadState` → баннер `#storage-alert` (8с warn / 4.5с ok); кросс-вкладочная синхронизация (storage-event → loadState+render); Esc-каскад документного уровня покрывает ВСЕ оверлеи при фокусе на body; у каждого бэкдропа stopPropagation в Escape-ветке; поиск автоочищается при опустении колоды («воскрешение» поиска); демо-колоды защищены от дублей (`DEMO_KEY`, кнопка «Добавлено ✓» disabled); bulk-hint предупреждает про первый «=»; countUp до 9999; тур перепозиционируется при resize |

---

## 7. Backend API

### 7.1 Auth Endpoints

| Method | Path | Description |
|---|---|---|
| POST | `/api/auth/register` | Register new user (email + password) |
| POST | `/api/auth/login` | Login, returns access + refresh tokens |
| POST | `/api/auth/refresh` | Refresh access token |
| POST | `/api/auth/logout` | Logout (revoke refresh token) |
| GET | `/api/auth/me` | Get current user profile |

### 7.2 Deck Endpoints

| Method | Path | Description |
|---|---|---|
| GET | `/api/decks` | List user's decks |
| POST | `/api/decks` | Create new deck |
| GET | `/api/decks/{id}` | Get deck by ID |
| PATCH | `/api/decks/{id}` | Update deck |
| DELETE | `/api/decks/{id}` | Delete deck |
| GET | `/api/decks/{id}/cards` | List cards (paginated, FTS search) |
| POST | `/api/decks/{id}/cards` | Add card to deck |

### 7.3 Card Endpoints

| Method | Path | Description |
|---|---|---|
| PATCH | `/api/cards/{id}` | Update card |
| DELETE | `/api/cards/{id}` | Delete card |
| PUT | `/api/cards/reorder` | Reorder cards (body: `{card_ids: [uuid, ...]}`) |
| POST | `/api/cards/{id}/image` | Upload card image (multipart) |
| DELETE | `/api/cards/{id}/image` | Delete card image |

### 7.4 Share Endpoints

| Method | Path | Description |
|---|---|---|
| GET | `/api/decks/share/{slug}` | Get public deck by slug |
| GET | `/api/decks/share/{slug}/cards` | Get public deck cards |
| POST | `/api/decks/{id}/share` | Enable sharing (generate slug) |
| DELETE | `/api/decks/{id}/share` | Disable sharing |

### 7.5 Study Endpoints

| Method | Path | Description |
|---|---|---|
| POST | `/api/study/session?deck_id={id}` | Start study session (deck_id as query param) |
| PATCH | `/api/study/session/{id}?known=N&unknown=N` | Update session progress (known/unknown as query params) |
| GET | `/api/study/stats` | Get user statistics |

### 7.6 Migration Endpoint

| Method | Path | Description |
|---|---|---|
| POST | `/api/migrate` | Migrate data from local storage |

### 7.7 Healthcheck

| Method | Path | Description |
|---|---|---|
| GET | `/api/health` | Basic healthcheck |
| GET | `/api/health/detailed` | Detailed healthcheck (includes DB status) |
| GET | `/api/metrics` | Prometheus-style metrics (requires auth) |

---

## 8. Infrastructure

### 8.1 Docker Compose

```
nginx (alpine) → backend (python:3.12-slim) → db (postgres:16-alpine)
```

- **Nginx:** reverse proxy, static files, rate limiting, SSL-ready
- **Backend:** FastAPI + uvicorn, healthcheck, non-root user
- **DB:** PostgreSQL 16, healthcheck, persistent volume

### 8.2 Environment Variables

| Variable | Default | Description |
|---|---|---|
| `SECRET_KEY` | `change-me-in-production` | JWT signing key |
| `DATABASE_URL` | `postgresql://user:pass@db:5432/flashcards` | Database connection (psycopg2 for SQLAlchemy and Alembic) |
| `ACCESS_TOKEN_EXPIRE_MINUTES` | 15 | Access token lifetime |
| `REFRESH_TOKEN_EXPIRE_DAYS` | 30 | Refresh token lifetime |
| `EMAIL_API_KEY` | `` | SendGrid API key |
| `EMAIL_FROM` | `no-reply@flashcards.app` | Sender email |
| `CORS_ORIGINS` | `["http://localhost", "http://localhost:3000"]` | Allowed CORS origins |
| `ALLOWED_HOSTS` | `["localhost", "*.localhost", "testserver"]` | Trusted hosts |
| `SECURE_COOKIES` | `False` | Enable secure flag for cookies (True in production) |
| `RATE_LIMIT_ENABLED` | `True` | Enable rate limiting on auth endpoints |

### 8.3 CI/CD

- **CI:** GitHub Actions — backend tests (pytest) + E2E (Playwright) on push/PR
- **CD:** GitHub Actions — build Docker image + deploy to VPS on push to main

---

## 9. Tests

### 9.1 Backend Tests (pytest)

| File | Coverage |
|---|---|
| `backend/tests/test_auth.py` | Registration, login, validation, /me |
| `backend/tests/test_decks.py` | CRUD, deck isolation between users |
| `backend/tests/test_cards.py` | CRUD, pagination, FTS search |
| `backend/tests/test_migrate.py` | Data migration |
| `backend/tests/test_health.py` | Healthcheck endpoints |
| `backend/tests/test_auth_extended.py` | Logout revoke, refresh, register dup, weak password |
| `backend/tests/test_share.py` | Share enable/disable, public access, isolation |
| `backend/tests/test_study_api.py` | Study session CRUD, validation, isolation |

### 9.2 E2E Tests (Playwright)

| File | Coverage |
|---|---|
| `tests-e2e/test_auth.py` | Register, login, logout flows |
| `tests-e2e/test_study.py` | Create deck, add cards, study mode |

### 9.3 Smoke Tests (PowerShell CDP)

30 scripts, 758 checks — full frontend smoke test suite. Run: `powershell -ExecutionPolicy Bypass -File tests\run-tests.ps1 [-Smoke] [-Parallel N] [-Filter name]`

---

## 10. Decisions Log

| Решение | Почему (why) |
|---|---|
| FastAPI + SQLAlchemy (backend) | Выбрано пользователем, современный async Python |
| PostgreSQL + FTS | Надёжная БД + полнотекстовый поиск на русском |
| JWT через httpOnly cookies | Безопаснее localStorage, защита от XSS |
| Docker Compose | Простой деплой, изоляция сервисов |
| Дуальное хранение (API + localStorage) | Онлайн-режим + оффлайн-режим + миграция |
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
| Без модулей/сборки (frontend) | Работа с `file://` без сервера; CORS-модули там не работают |
| Reduced-motion: грани через `display` | 3D-трансформ отключён глобально, поэтому флип эмулируется показом нужной грани |
| Summary поверх фокуса (z-index 66 динамически) | Итог раунда не должен выгонять из полноэкранного режима: квиз/карта продолжаются после закрытия итога; статический z-index ломал бы stats-over-summary, поэтому поднимается только при открытом фокусе |
| Маршрутизация ✕/Esc фокуса по `quizFullscreen` | Одна кнопка ✕ обслуживает два режима фуллскрина; без маршрутизации выход из квиза вызывал бы `exitFocusMode` и молча ничего не делал |
| showLayer/hideLayer вместо 12 копий add-class+reflow | Оверлей-паттерн дублировался в каждом окне; единые хелперы в modal.js убрали ~50 строк копипасты |
| Делегирование событий строк списка на контейнер | Пер-строчные листенеры (click + 4 DnD) на 404 строках = ~2400 подписок на рендер; делегирование в `bindCardRowsDelegation` убирает их и память |
| Heavy-mode списков (>60 строк без row-in) | Массовая вставка 400 анимаций одновременно давала ~70мс на рендер; отключение построчных анимаций на больших партиях убирает пик без потери UX на малых |
| Флаг `--allow-file-access-from-files` удалён из харнесса | Отключение same-origin для file:// — приманка для эвристик Defender; не нужен (нет XHR), побочный эффект (cssRules SecurityError) обойдён computed-style проверками |
| Зона tilt — стабильная обёртка, а не живой rect карты | Наклон сдвигает хит-квадрат карты: замер по нему = петля обратной связи и мерцание у края; обёртка не трансформируется и чуть шире — эффект стабилен вплоть до кромки |
| Правило «одна карточка — одно событие за раунд» (`scoredStatus` Map) | Повторный клик «Знаю» и флип+«знаю» накручивали дневные счётчики (5 кликов = +5 «изучено»); метрики меню разошлись бы с итогом раунда. Первая отметка карты в раунде фиксирует событие; новые раунды начинают отсчёт заново |
| stopPropagation в Escape-ветке КАЖДОГО бэкдропа | Esc на настройках всплывал в документ, а расширенный каскад closeTopModal закрывал следующий слой (меню) — регрессия поймана зондом; единый инвариант: свой обработчик гасит событие, документный работает только при фокусе на body |
| Кросс-вкладочная синхронизация через storage-event | Две вкладки одного файла молча перетирали данные друг друга (последняя сохранение побеждает); теперь внешнее изменение adopting через loadState+render |
| Импорт колоды сливается в существующую по имени | Повторный импорт того же файла обязан быть идемпотентным: иначе каждая загрузка создаёт дубль колоды с копиями карт; сигнатурная дедупликация (deck+question+answer) добивает остатки |
| CSV — диалект `deck;question;answer;status` | Первый столбец сохраняет структуру колод при полном экспорте; 3-колоночная форма принимается как «в текущую колоду»; кавычки с удвоением покрывают `;` и переводы строк внутри полей |
| Тесты кликают кнопки меню действий по тексту, не по индексу | Меню действий расширилось (экспорт колоды), числовые индексы сдвинулись и сломали сразу несколько наборов — поймано полным прогоном |
| Изображения — IndexedDB вне JSON-базы + сильное сжатие | localStorage (~5МБ) не выдержал бы dataURL; IDB снимает лимит. 480px/WebP q0.6 выбрано пользователем: фото ~20-60КБ, сотни картинок в запасе; текст вопроса/ответа остаётся крошечным и полностью портируемым через экспорт |
| Hover-цвет точек «⋯»: light = mix(accent 72%, ink), dark = accent-2 | Свип WCAG 10 палитр × 2 темы: базовый accent в тёмных темах даёт 1.9–2.9 на тёмной карте (violet/indigo/slate/berry), светлое золото на креме 2.36; accent-2 в темноте поднимает до 4.3–7.9, подмес чернил в свету — до 3.55+. Замерять арифметикой токенов через probe-resolve: canvas-декодер падает на color()/color-mix, синтетический mouseover не ставит :hover |
| View-transition анимация — CSS-keyframes, не JS `animate()` | JS-вариант (`await ready → animate`) содержал гонку: на занятом основном потоке Chrome успевал запустить дефолтный кроссфейд group-слоя (250мс), наша анимация цеплялась позже и обрывалась его финалом — «анимация доходит до середины и щёлкает до конца» у реальных пользователей. CSS-keyframes подхватываются автоматически при появлении псевдоэлемента — гонки не существует по построению; дефолты group/old заглушены явно |
| Иконка озвучки — inline SVG на грани, не эмодзи на панели | Эмодзи имеет собственную чёрно-белую обводку и не окрашивается темой; SVG со stroke=currentColor наследует `--ink`/accent; размещение на карте устраняет разрыв контекста (действие над картой — на карте) и работает в фокус-режиме бесплатно |
| Реверс через записи `id#rev`, а не дубли карт | Отдельные реверс-карты раздули бы данные и списки; суффикс в studyOrder даёт нулевой оверхед хранилища, а счётчики раунда, итог и повторы автоматически получают честную семантику «позиций раунда» |
| stopPropagation не действует на СОСЕДНИЕ листенеры того же узла | Клик `.face-speak` и flipCard висят на одном #flashcard: погасили всплытие — flipCard всё равно получил событие; нужен guard внутри самого обработчика (`closest('.face-speak')`) |
| Чередующиеся оценки одной карты в тестах | В двустороннем раунде одна карта отмечается несколько раз; «known затем unknown» оставляет статус unknown (последняя запись решает) — тестовые ожидания должны быть детерминированы |
| IDB-ответы приходят позже рендера — нужен race-guard | `showStudyCard` запускает `imgGet` асинхронно; при быстрой навигации ответ устаревшей карточки может прийти последним и «приклеиться» к чужой карте — токен по id текущей карточки сверяется в момент разрешения промиса |
| Картинки не входят в экспорт JSON/CSV | IDB и localStorage — раздельные хранилища; перенос базы с картинками потребовал бы zip/встроивание dataURL в JSON (раздувание файла в десятки МБ). Осознанное ограничение Фазы 2, задокументировано в §5.6 |
| Inline-слушатели + делегирование на одном списке = двойной вызов | При внедрении делегирования inline-хвосты кнопок строк не вычистили — edit/delete срабатывали дважды; E2E не ловит КРАТНОСТЬ вызовов (конечное состояние то же) — при дублировании путей обработки событий проверять количество модалок/вызовов, не только итог |
| Фича без теста «на существование» теряется в рефакторах | Heavy-mode (>60 строк без row-in) был внедрён и потерян при последующих правках: CSS-класс `.no-anim` остался, JS-переключатель исчез; ни один тест не проверял его наличие — внешние аудиты ловят такое мгновенно |
| Псевдоэлементы наследуют CSS-переменные от ПОРОЖДАЮЩЕГО элемента | `::view-transition-new(root)` читает `--bloom-x/y` из `<html>`; установка переменных на `#theme-bloom` (даже с теми же именами) до псевдо не доходит — координаты дублируются на корень |
| Координаты клика для view-transition — ТОЛЬКО в процентах окна | При системном масштабировании (dpr 1.5 у пользователя) пиксельные circle(at Xpx Ypx) рисуются в пространстве растрового снапшота и «стекают» к левому верхнему углу пропорционально удалённости точки; проценты (x/innerWidth*100%) инвариантны к масштабу. Диагностика: маркеры на странице + строка localStorage, телеметрия clip-path через getComputedStyle(html,'::view-transition-new(root)') |
| У view-transition есть ТРИ дефолтные анимации, а не одна | Chrome запускает кроссфейды на `group`, `old` и `new` слоях (250мс); глушить нужно все три (`animation:none`), иначе «щелчок» в середине кастомной анимации; headless-чистый профиль эту гонку НЕ воспроизводит — проверять телеметрией `document.getAnimations()` с фильтром по pseudoElement (element.getAnimations() псевдо не возвращает) |
| Единый WAAPI-драйвер флипа вместо CSS-анимаций | Вращение карты и scaleX тени были двумя независимыми композиторными анимациями с разными механизмами старта (класс vs `:has()`-гейт) — на живом GPU дрейфовали друг относительно друга; общий `element.animate()` в одном такте гарантирует общее время старта, а реверс продолжается с текущего угла без скачка |

---

## 11. Pitfalls

- `el.style.background = ...` (шорткат) затирает `background-image` → юзать `backgroundColor`.
- `var()` внутри `@keyframes` ненадёжен → в ключевых кадрах тени литералы `translate(6px, 7px)`.
- Сдвиг тени карты задан в ТРЁХ местах синхронно: `.flashcard-wrap::before`, `#focus-wrap::before`, WAAPI-кадры в `startFlipAnimation` (+ отдельная амплитуда в `card-swap-shadow`) — менять только все сразу, иначе флип разойдётся со статикой.
- Любой `transform` на предке создаёт 3d-context: тень внутри начнёт резаться — держать её на плоских обёртках.
- Класс `was-flipped` снимается только при смене карточки — он нужен гейтам обратной анимации; не «чистить» его лишний раз.
- После правок CSS поднимать `?v=N` у `<link>` в index.html — иначе кэш браузера покажет старое.
- Сиды тестов — с динамической датой (суточный сброс).
- `void el.offsetWidth` перед добавлением анимационного класса обязателен (рестарт анимации).
- Функции глобальные — новые имена проверять на коллизии по всем файлам.
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
- `?v= нужен на ВСЕХ ассетах, не только CSS | Кэшировался старый ui.js под новым style.css: координаты писались не на <html>, круг шёл из фолбэка 50%/50% («всегда из той же точки»). Лечение: версионировать каждый <script src> + детектор — head-скрипт хранит __ASSET_V, app.js ставит __RUNTIME_V; расхождение через секунду после load показывает toast «Ctrl+F5» (старый код сам себя поймать не может) |
- У `Map` нет метода `.add` (только `.set`) — опечатка внутри click-обработчика даёт неперехваченное исключение, которое в тестах выглядит как `Script error.` в `__errs`, а не как падение сценария.
- Тесты, кликающие кнопки меню действий колоды, не должны использовать числовые индексы (`[3]`) — состав меню меняется; искать по `textContent.includes("...")`.
- **Backend: lazy loading в sync SQLAlchemy** — использовать `selectinload()` для relationships, иначе `MissingGreenlet` error.
- **Backend: JWTError импорт** — в `dependencies.py` нужен `from jose import jwt, JWTError`.
- **Backend: email status code** — SendGrid возвращает 202, не 200.
- **Backend: deck_id тип** — в API endpoints использовать `UUID`, не `str`.

---

## 12. Product Principles

Выжимка из продуктового исследования (исходник удалён, принципы канонизированы здесь):

1. **Active recall прежде всего**: переворот — момент вспоминания; сначала думает, потом видит ответ.
2. **Скорость создания**: карточка ≤ 10 секунд; массовый ввод «вопрос = ответ» построчно.
3. **Два разделённых режима**: «Карточки» (создание) и «Учить» (изучение); focus-режим — один объект на экране.
4. **Самооценка после ответа**: «Знаю / Не знаю», результат сразу в статистику.
5. **Видимый прогресс**: счётчик сегодня, серия дней, проценты колод, 7-дневные мини-графики, лог сессий.
6. **Мгновенный старт**: библиотека готовых колод — учиться можно без создания своего.
7. **Офлайн-capable**: работает без сети через localStorage; данные можно мигрировать на сервер.
8. **Доступность**: тёмная тема, focus-trap, aria-атрибуты, reduced-motion, крупные зоны нажатия.
9. **Мотивация серией**: streak показывается от 2 дней подряд.

---

## 13. Roadmap Priorities

| Приоритет | Задача | Статус |
|---|---|---|
| High | Настроить SSL на VPS (Let's Encrypt) | ⏳ |
| High | Настроить email-провайдер (SendGrid) | ⏳ |
| Medium | Полная миграция фронтенда на API | ⏳ |
| Medium | Service Worker для оффлайн-режима | ✅ Реализован (sw.js) |
| Low | Elasticsearch для продвинутого поиска | ⏳ |
| Low | Мобильное приложение (PWA) | ⏳ |

---

## 14. Known Issues

| Issue | Status | Workaround |
|---|---|---|
| `password[:72]` silent truncate in `hash_password` | ⚠️ Known | Password longer than 72 bytes is silently truncated by bcrypt limitation |
| In-memory rate limiting doesn't work across replicas | ⚠️ Known | Use Redis for multi-instance deployments |
| `deck_to_response` still has fallback `len(deck.cards)` | ⚠️ Known | All callers now pass `cards_count` explicitly |
| `get_public_deck` makes 2 SQL queries (deck + count) | ℹ️ Minor | Acceptable for public deck viewing (low frequency) |
| Frontend `storage.js` and API `Data` layer can be out of sync | ⚠️ Known | Use "Migrate" button to sync localStorage → server |
| No CSRF protection on cookie-based auth | ℹ️ Planned | Add CSRF tokens in future iteration |

---

## 15. Conventions

Как есть в проекте (не жёсткие запреты, а сложившийся стиль — следуй ему):

- Vanilla ES2020+: `const/let`, стрелки, шаблонные строки, деструктуризация; без TS, без JSDoc-типов.
- Комментарии в коде практически отсутствуют (единственное исключение — пояснение в head-скрипте index.html); самодокументирующие имена.
- ID и CSS-классы — kebab-case; функции и переменные — camelCase; глобальные функции без префиксов.
- Строки UI — русский, прямо в коде.
- CSS: секции с баннерами `/* ==== Имя ==== */`, переменные тем в блоках `html[data-mode]` / `html[data-palette]`.
- Новые списки рендерить через `DocumentFragment`; точечные обновления предпочитать полному `render()`.
- Любое изменение стилей сопровождается подъёмом `?v=N` и прогоном затронутых тестов; структурные изменения — прогоном всех 30.
- **Backend:** sync SQLAlchemy (psycopg2), type hints, Pydantic schemas для валидации.
- **Backend:** все роутеры в `app/routers/`, сервисы в `app/services/`.
- **Backend:** тесты в `backend/tests/`, фикстуры в `conftest.py`.
