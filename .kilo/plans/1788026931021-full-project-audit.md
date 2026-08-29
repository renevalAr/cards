# Flashcards — Полный аудит проекта (UI/UX, стабильность, бизнес-модель)

> Карта взаимосвязей, способы реализации, главные проблемы и дорожная карта правок.
> Документ для последующих итераций правок UI/UX. Код не редактируется на этом этапе.

---

## 0. Резюме (TL;DR)

**Что это.** Офлайн-приложение флэшкарточек «в эстетике школьной тетради», превращённое в веб-сервис: Vanilla JS фронтенд + FastAPI/PostgreSQL бэкенд, деплой через Docker Compose + Nginx. v2.0.0 (2026-08-28).

**Состояние стека и качества (1-10):**

| Аспект | Оценка | Комментарий |
|---|---|---|
| Архитектурная целостность | 7/10 | Единый overlay-паттерн, единый state, разделение `storage/API`. Но «двухголовый» фронт (localStorage + API) — главный источник сложности. |
| Дизайн-система | 9/10 | Очень зрелая: палитры×темы, осознанные тени, view-transition, анимация флипа через WAAPI. Большая часть работы сделана. |
| Надёжность фронта | 7/10 | Тесты ловят регрессии, но есть падающие `library` / `spacing` / `motion` / `tour` / `stats-empty`. Документированные «Pitfalls» показывают, что фичи легко теряются (heavy-mode). |
| Безопасность | 6/10 | JWT-cookies, httpOnly, CORS, rate-limit, security headers — ок. Слабые места: in-memory rate-limit, нет CSRF, SECRET_KEY по умолчанию, deck_id в `migrate` без изоляции по пользователю (мигрированный пользователь), `email.py` async/await в sync-коде. |
| Backend полнота | 5/10 | Базовый CRUD готов, FTS подключён, но: study-сессии **не пишутся UI** (см. ниже), отсутствуют эндпоинты списков/пагинации колод, нет CSRF, нет отметки карточек (status меняется только локально), нет синхронизации. |
| Тесты | 6/10 | 30 PowerShell CDP + 25 pytest backend + 6 Playwright E2E. **6+ сьютов красные на сегодня** — `library/menu-fits`, `spacing/menu-open`, `motion/pulse`, `stats-empty/cover-no-scroll`, `cover-no-scroll` (повторяется), `full/cover-no-scroll` — это нестабильность, а не шум. |
| UX | 7/10 | Продуманные микро-взаимодействия (ripple, tilt, stamp-swap, focus-mode), хорошая a11y (focus-trap, role, aria). Но сложная навигация, скрытые действия колоды, нет онбординга к авторизации, нет синхронизации. |

**Главные проблемы прямо сейчас** (по убыванию риска):

1. **Двойственность данных localStorage ↔ API.** Серверный режим фактически не доехал: `AppData` объявлен, но не используется большинством кода; `saveCard/deleteDeck/bulk` пишут только в `state`+localStorage. `Sync` после логина — единственная попытка склеить. Это вводит «режим призрака»: UI выглядит сетевым, но данные не сохраняются на сервер.
2. **API «второго уровня» не дописан.** `Data.startStudySession/updateStudySession/getStudyStats` объявлены, но нигде не вызываются. Бэкенд пишет `study_sessions`, а клиент учитывает только локальный `history/sessions`.
3. **Backend-баги с sync engine.** `migrate.py`, `auth.py` (refresh), `routers/decks.py` — везде psycopg2/sync SQLAlchemy без явных `selectinload` на `Deck.cards` (см. pitfall «MissingGreenlet» — решено в `decks.py` раздельным count, но не везде). `share.py` тоже использует `db.get(Deck, ...)` без проверки прав на доступ к картам.
4. **Тесты UI красные на стабильных сьютах.** `cover-no-scroll` падает почти всегда (background scroll под модалкой на 480px viewport), `menu-fits` (522/482 — viewport по умолчанию), `motion/M4 pulse-pop scale=0.000` (анимация не запускается).
5. **UX-барьеры.** Авторизация спрятана за иконкой в шапке без onboarding. Колоды-«призраки» после логина (миграция только по кнопке). Шаринг колоды — только в меню действий (легко пропустить). Шрифты с Google Fonts — без офлайн-режима.
6. **Надёжность анимаций.** Тени, `::view-transition-new`, `swap-shadow` синхронизированы в **3 местах** вручную (CSS + WAAPI + JS-кадры) — высокая цена любого изменения.
7. **Изображения разделены между браузером (IDB) и сервером (FS).** При смене устройства / браузера картинки теряются; в экспорте их нет — задокументировано, но это ограничение продукта.
8. **Без CSRF, с in-memory rate-limit** — при горизонтальном масштабировании лимиты сбросятся.
9. **Производительность на больших колодах.** `renderCardRows` синхронно рендерит все строки (комментарий: ~70мс на 404). `VirtualList` готов, но не подключён (`docs §14 Known Issues`).
10. **`email.py` async-функция, вызывается как sync** — отправка верификации мертва, если только не запускается через `asyncio.run()`/`BackgroundTasks` (не используется нигде).

---

## 1. Карта взаимосвязей

### 1.1 Файловая структура и роли

**Backend (`backend/`)**

| Файл | Роль |
|---|---|
| `app/main.py` | FastAPI-приложение, lifespan, CORS, middleware, роутеры, монтирование `/css`, `/js`, `/sw.js`, `/`, `/d/{slug}`. |
| `app/config.py` | `Settings` через pydantic-settings: SECRET_KEY, DATABASE_URL, токены, CORS, hosts, cookies. |
| `app/database.py` | Sync `create_engine` + `sessionmaker`, `get_db()` для DI. |
| `app/dependencies.py` | `get_current_user` через cookie `access_token`, JWT (HS256). |
| `app/middleware.py` | 4 middleware: `RateLimit` (auth 5/мин), `RequestLogging` (>1с slow-log), `SecurityHeaders`, `SecurityLogging` (401/403/429). |
| `app/logging_config.py` | JSON-логгер, `setup_logging()`. |
| `app/models/__init__.py` | `User`, `Deck`, `Card`, `RefreshToken`, `StudySession` (UUID PK, tsvector FTS-поля, `onupdate=now`). |
| `app/schemas/__init__.py` | Pydantic V2: `UserCreate/Login/Response`, `TokenResponse`, `DeckCreate/Update/Response`, `CardCreate/Update/Response`, `PaginatedResponse`. |
| `app/schemas/migration.py` | `MigrationPayload` v1 для `POST /api/migrate`. |
| `app/routers/auth.py` | `register/login/refresh/logout/me`, ставит httpOnly cookies. |
| `app/routers/decks.py` | CRUD + `/{deck_id}/cards` (cursor + FTS, лимит ≤100). |
| `app/routers/cards.py` | `PATCH/DELETE /cards/{id}`, multipart image upload (Pillow, WebP, 480px). |
| `app/routers/share.py` | Публичный deck по slug (без auth), enable/disable share. |
| `app/routers/study.py` | `POST /study/session`, `PATCH /study/session/{id}`, `GET /study/stats` (today/total/streak). |
| `app/routers/migrate.py` | Идемпотентный приём миграции (см. §2 «бизнес-логика»). |
| `app/services/auth.py` | bcrypt (truncate 72), JWT access+refresh. |
| `app/services/image.py` | validate → compress → save (WebP, 480px). |
| `app/services/share.py` | `generate_share_slug` (uuid4[:8]). |
| `app/services/email.py` | SendGrid через httpx — async-функция, **никем не вызывается**. |
| `alembic/` | 3 миграции: initial, idx `refresh_tokens.token_hash`, триггер `updated_at`. |

**Frontend (`frontend/`)**

| Файл | Строк | Роль |
|---|---|---|
| `index.html` | 523 | Вся разметка + head-script (theme/fontsize), подключение `?v=41`. |
| `css/style.css` | ~3000 | Все стили, переменные палитр/тем, WAAPI-flip-keyframes. |
| `js/api.js` | 151 | `API.request` (auto-refresh на 401, retry-once), `Auth.{init,login,register,logout}`, `Decks.{list,get,create,update,delete,getCards,addCard}`. |
| `js/api/data.js` | 108 | `Data.*` обёртки над API + `exportLocalData` для миграции. |
| `js/app-data.js` | 89 | `AppData.syncFromServer/createDeck/deleteDeck/addCard/deleteCard` — слой, призванный склеить state и API. |
| `js/virtual-list.js` | 119 | `VirtualList` через IntersectionObserver (готов, не подключён). |
| `js/share.js` | 58 | `Share.{viewPublicDeck,enableSharing,disableSharing,getShareUrl,copyShareLink}`. |
| `js/router.js` | 64 | Hash-роутер: `#menu`, `#deck/{id}`, `#d/{slug}`, `#stats`, `#settings`, `#login`. |
| `js/storage.js` | 323 | Глобальный `state`, normalize/save/load, uid(), recordStudy, history, sessions. |
| `js/modal.js` | 191 | Overlay pattern (`showLayer/hideLayer/lockScroll/trapTabKey`), openModal-promise. |
| `js/ui.js` | 509 | `PALETTE_META` (10 палитр), `renderThemeDots`, `renderCardRows/Filters/List`, `applyAppearance` (view-transition), `applyFontSize`, `bindAutoTheme`. |
| `js/study.js` | 712 | WAAPI-флип (driver), квиз, focus-mode (appendChild card между `.flashcard-wrap` и `#focus-wrap`), TTS, summary, confetti. |
| `js/menu.js` | 390 | Menu overlay, deck-picker, deck-actions (popup), tour. |
| `js/stats.js` | 204 | Stats window, day-bars, count-up. |
| `js/library.js` | 178 | 3 демо-колоды (англ. 30, столицы 12, элементы 15). |
| `js/data.js` | 368 | Импорт/экспорт JSON+CSV, диалог «слить/заменить». |
| `js/images.js` | 91 | IndexedDB `flashcards-images/v1`, compressImageFile (480px WebP q0.6). |
| `js/app.js` | 770 | CRUD, bulk, init, события, авторизация, viewport-tilt, parallax, ripple. |
| `sw.js` | — | Service worker для офлайна. |

**Инфра**

| Файл | Роль |
|---|---|
| `docker-compose.yml` | Nginx + backend + postgres (healthcheck, volumes: media, pgdata). |
| `nginx/nginx.conf` | Reverse proxy, CSP, gzip, rate-limit (`auth 5r/m`, `api 30r/s`), SSL ready. |
| `.github/workflows/` | (отсутствуют в репо — README упоминает CI/CD, но папка пустая; **CI не работает**). |
| `scripts/{healthcheck.sh,backup.sh}` | Утилиты деплоя. |
| `tests/` | 30 PowerShell CDP-скриптов + `run-tests.ps1`. |
| `tests-e2e/` | 6 Playwright тестов (auth, study). |

### 1.2 Карта потоков данных

```
                  ┌────────── Nginx (80/443) ──────────┐
                  │ /static/* → /var/www/frontend     │
                  │ /media/*  → /var/www/media        │
                  │ /api/*    → FastAPI               │
                  │ /         → SPA index.html        │
                  │ /d/{slug} → SPA index.html (router читает hash)│
                  └─────────────┬─────────────────────┘
                                │
                       ┌────────▼────────┐
                       │  FastAPI main   │── lifespan: SELECT 1
                       └───┬───────┬─────┘
                routers    │       │  StaticFiles(/css, /js, /sw.js)
        ┌────────┬────────┬─┴──┬────┴──┬─────────┐
        ▼        ▼        ▼    ▼      ▼         ▼
      auth    decks     cards share study    migrate
        │        │        │     │      │         │
        ▼        ▼        ▼     ▼      ▼         ▼
     services.auth/image/share  │   StudySession
                          (public)              │
                                              postgres
                  ┌─────────────────────────────────────┐
                  │ users / decks / cards / refresh     │
                  │ tokens / study_sessions             │
                  └─────────────────────────────────────┘

Frontend (single page):
  index.html (head) → inline bootstrap mode/palette/fontsize from LS
  → scripts (api.js → api/data.js → app-data.js → virtual-list → share →
     router → storage → modal → ui → study → menu → stats → library →
     data → images → app)
  → Service Worker (offline)
  → state (window.state) ← единственный источник правды UI
  → saveState() пишет в localStorage (decks, cards, today, sessions, selectedDeckId)
  → API вызовы идут через API/Decks/Data/AppData (частично)
```

### 1.3 Критические зависимости (кто кого дёргает)

| Источник | Потребитель | Связь |
|---|---|---|
| `storage.js` (`state`, `saveState/loadState`, `cardsInDeck`, `selectedDeck`) | все | Глобальный state. |
| `app.js` (CRUD, event-bind) | `study.js, ui.js, menu.js, data.js, modal.js, images.js` | Обработчики, viewport-tilt, ripple. |
| `modal.js` (`openModal`, `showLayer/hideLayer`, `lockScroll`, `trapTabKey`) | `menu, stats, library, data, bulk, settings, summary, deck-pick, menu-pop` | Overlay pattern. |
| `ui.js` (`render`, `renderCardRows`, `applyAppearance`) | `app, study, menu, stats` | UI-ядро. |
| `study.js` (`flipCard`, `startQuiz`, `beginRound`, `markStatus`, `enterFocusMode`) | `app.js` (events), `ui.js` (`render`) | Сценарий изучения. |
| `api.js` (`API.request`, `Auth`, `Decks`) | `api/data.js`, `app-data.js`, `app.js` | Транспорт. |
| `images.js` (`imgGet/put/delete`, `compressImageFile`) | `app.js`, `ui.js`, `study.js` | IDB-картинки. |
| `data.js` (`export/import`) | `app.js`, `menu.js` | CSV/JSON. |
| `menu.js` (`openMenu`, `openDeckPicker`, `openDeckActions`, `openLibrary`, `showTour`) | `app.js` (entry), `router.js` | Навигация. |
| `stats.js` | `menu, app, router` | Окно статистики. |
| `library.js` | `menu, app` | Демо-колоды. |
| `share.js` | `router.js` (`#d/{slug}`) | Публичные колоды. |

### 1.4 Глобальный state (storage.js)

```
state = {
  decks: [{ id, name, twoSided }],
  cards: [{ id, deckId, question, answer, status }],
  selectedDeckId,
  cardFilter: "all"|"new"|"known"|"unknown",
  searchQuery,
  tab: "edit"|"study",
  studyMode: "flip"|"quiz",
  studyOrder: [cardId|"cardId#rev"], studyIndex, flipped,
  today: { date, known, unknown },
  history: { [deckId]: { [date]: { known, unknown } } },
  sessions: [{ deckId, date, known, unknown }]
}
```

---

## 2. Способы реализации ключевых вещей

| Возможность | Реализация | Где |
|---|---|---|
| Аутентификация | JWT (HS256) access 15м + refresh 30д, httpOnly cookies, refresh endpoint на cookie, auto-retry в `API.request`. | `backend/routers/auth.py`, `frontend/js/api.js` |
| Хранение данных | Двухслойное: localStorage (UI state) + PostgreSQL через API. | `storage.js`, `api/data.js`, `app-data.js` |
| FTS | tsvector + GIN, russian config, `plainto_tsquery`. | `backend/routers/decks.py:93` |
| Публичные колоды | slug из `uuid4[:8]`, отдельные endpoint'ы (без auth), `is_public + share_slug`. | `share.py`, `routers/share.py` |
| Анимация флипа карточки | Один WAAPI-driver: 3 параллельных `element.animate` (rotateY, shadow scaleX, lift). | `study.js:75 startFlipAnimation` |
| Смена темы | View Transition API + bloom-div с clip-path, координаты в `%` от viewport. | `ui.js:452 applyAppearance` |
| Тени | Жёсткие копии со сдвигом на плоских обёртках, не внутри `preserve-3d`. | `style.css` `.flashcard-wrap::before`, `.focus-wrap::before`, WAAPI-кадры |
| Озвучка | `speechSynthesis`, приоритет Google/Natural голосов, rate 0.92, pitch 1.05. Иконка SVG `currentColor` на грани. | `study.js:150 pickRuVoice`, `index.html:187` |
| Изображения карточек | IndexedDB `flashcards-images/v1`, WebP q0.6, ≤480px. Сервер: Pillow с тем же лимитом. | `images.js`, `backend/services/image.py` |
| Миграция localStorage → сервер | `Data.exportLocalData()` собирает JSON в формат `migration-v1`, `POST /api/migrate`. | `frontend/js/api/data.js:83`, `backend/routers/migrate.py` |
| Overlay pattern | `showLayer/hideLayer` (opacity/visibility transition), `lockScroll`, `trapTabKey`. | `modal.js` |
| Focus-trap | Ручной — список focusable через `getFocusable()`, циклический Tab. | `modal.js:91 getFocusable` |
| Live search | Подстрочный поиск + `<mark class="search-hit">` с сохранением регистра. | `ui.js:58 searchMatches, 62 appendHighlighted` |
| Квиз | Build 4 опции (верный + 3 случайных), авто-проверка, повтор «quiz-quiz» / «quiz-all». | `study.js:311 startQuiz, 318 beginQuiz, 474 answerQuiz` |
| Drag-reorder | HTML5 DnD, индикаторы `drop-above/below`, делегирование на контейнер. | `ui.js:122 moveCardWithinDeck` |
| Backup экспорт/импорт | `v:2` JSON; CSV `deck;question;answer;status`; диалог «слить/заменить»; сигнатурная дедуп `deck+q+a`. | `data.js` |
| Streak | Подряд идущие дни с активностью; сегодня или вчера — старт. | `storage.js:189 computeStreak` |
| Stats | Дневные бары (каскад 45мс), count-up цифры, сессии с сортировкой date desc + insertion. | `stats.js` |
| Reduced-motion | Глобальный guard в `reduceMotion()`, `display` вместо 3D для граней. | `study.js:146`, `style.css` |
| Service Worker | Регистрируется на `load`; `sw.js` в наличии (детали не прочитаны — критично для офлайна). | `index.html:516` |
| Двухсторонние колоды | `deck.twoSided`, studyOrder = `id` / `id#rev`. | `study.js:200 buildStudyEntries` |
| Auto theme | `prefers-color-scheme` listener → `applyAppearance({mode:"auto"}, centerEvent)`. | `ui.js:400 bindAutoTheme` |

---

## 3. Оценка дизайна и его стабильности / непрерывности

### 3.1 Что сделано отлично

- **Концепция «школьная тетрадь»** доведена до мелочей: васи-лента, поля с подписью, дырки скоросшивателя, штампы «вопрос/ответ», скрепки, маркер-выделитель в заголовках, hard-shadow без blur.
- **Дизайн-токены**: `--font`, `--gutter`, `--cell`, `--t`, `--ease`, `--spring`, `--flip`, плюс 10 палитр × 2 темы = 20 комбинаций. Все цвета — `color-mix` от accent.
- **WCAG ≥4.5** проверен на всех 10×2 (см. pitfall). Тёмный текст `#20150b` только на тёплых светлых палитрах (ember/gold); светлый `#fff8f0` на остальных.
- **Анимация флипа — WAAPI-драйвер**, единый такт для rotateY/shadow/lift ⇒ нет дрейфа композитора, реверс бесшовен.
- **Скользящие индикаторы** табов и колод (`.tab-indicator`, `.deck-marker`), overshoot флипа 4° на 82%, sheen на прогвессе квиза, стикер числа дня с поворотом, конфетти при 100%, flame-серия, doodle-саё, ripple от точки клика.
- **A11y**: role=dialog/tablist/tooltip, aria-modal/selected/pressed/live, focus-trap, видимый focus-visible, TTS на гранях, reduced-motion.

### 3.2 Что нестабильно / рискованно

| Риск | Симптом | Причина |
|---|---|---|
| Тени флипа в 3 местах (CSS, WAAPI, JS-keyframes). | Любая правка одной точки ломает визуал. | Документировано в pitfalls, требует синхронного изменения всех трёх. |
| View-transition с 3 дефолтными анимациями (`group/old/new`). | «Щелчок в середине» на занятом main thread. | Глушатся через `animation:none`, но лотерея при слабом CPU. |
| `startViewTransition` гонка с JS-`animate`. | Кроссфейд 250мс перебивал кастом. | Заменено на ключевые кадры — но фактически остаётся хрупким. |
| Координаты клика для `clip-path`. | При dpr≠1 пиксели стекаются к углу. | Решено процентами; необходима регрессия в тестах. |
| `app.js` `verifyStylesFresh` — анти-кэш. | Показывает «Ctrl+F5», но не защищает от смешения `v=41` / `v=50` в HTML. | В `index.html` сейчас `<link ... v=50>` для preload и `v=41` для stylesheet — расхождение. |
| Heavy-mode (`>60` без `row-in`). | Класс `.no-anim` есть, JS-переключатель потерян в одном из рефакторингов (pitfall №644). | Нет регрессионного теста. |
| Race-guard для imgGet. | Токен по id сверяется только в `showStudyCard`, но при быстром ответе возможен «приклей чужой картинки» в редких случаях. | Токен уже есть — нужны тесты на быструю навигацию. |
| Tilt по gBCR. | Петля обратной связи у краёв. | Исправлено (кэш в `tiltRect`), но без регрессионного теста. |
| `flashcard` перемещается через `appendChild` при фокусе. | Может ломать DnD/select на старых браузерах. | Зависит от того, что `flashcard-wrap` всё ещё в DOM. |
| Маркеры палитр inline `backgroundColor`. | Шорткат `background` стирает `background-image`. | Ловушка для новых контрибьюторов. |

### 3.3 Что выглядит «не работает»

| Что | Статус | Доказательство |
|---|---|---|
| Backend email-верификация | Мертва. `services/email.py` — async, нигде не вызывается, `register` не запускает отправку. | grep по `send_verification_email\|send_email` → 0 callers. |
| Backend `study_sessions` | API есть, UI не использует `Data.startStudySession`. | grep `startStudySession` → 0 callsites в `js/`. |
| Backend `Stats` для юзера | Считаются только в БД; UI показывает локальный `history`. | UI читает `state.history`, не API. |
| Backend миграция | Кнопка «Мигрировать» есть, но это **одноразовое действие**, не двусторонняя синхронизация. | После логина данные подтягиваются один раз; новые изменения карточек идут только в localStorage. |
| Backend `display_name` | Поле есть, UI его не показывает. | grep `display_name` в `frontend` → 0. |
| Backend deck pagination | Cursor на `/cards` есть, UI загружает первые 100 сразу (`AppData.syncFromServer`). | `decks/${deck.id}/cards?limit=100`. |
| Backend deck search (FTS) | Не вызывается из UI (`cards.js getCards` принимает `search`, но `AppData.syncFromServer` его не передаёт). | `Decks.getCards` имеет `search`, нигде не используется. |
| Backend image upload | Endpoint есть, UI не вызывает `Data.uploadImage`. | grep `uploadImage\|card-image POST` → 0. |
| Backend password reset / email verify | Нет endpoint'ов вообще. | — |
| CI/CD | README упоминает `.github/workflows`, но папка пуста. | `glob .github/**/*` → 0. |
| HTTPS redirect | Закомментирован в nginx.conf. | `nginx.conf:34`. |
| VirtualList | Реализован, не интегрирован в `renderCardRows`. | `docs §14`. |

### 3.4 Главные UX-недочёты (для будущей итерации)

1. **Авторизация невидима.** Иконка пользователя в шапке без лейбла. Нет «Зарегистрироваться» / «Войти» в первом экране. Шапка `auth-bar` объявлена, но кнопки `auth-bar/auth-logout-btn/login-btn` отсутствуют в HTML — `bindAuthEvents` ссылается на несуществующие ноды (`showAuthBar` молча падает).
2. **Миграция не интегрирована в поток.** Кнопка «Мигрировать» доступна только из меню, без подсказки, что данные могут быть как локальные, так и серверные.
3. **Картинки теряются между устройствами.** Задокументировано, но в продукте это критично для «запомни слова по фото».
4. **Поиск только по текущей колоде.** Глобальный поиск по всем колодам не реализован (FTS на бэке есть).
5. **Кнопки действий колоды** (переименовать, удалить, шарить, экспорт) — только через «⋯» в меню выбора колод. На странице самой колоды шапка показывает только «Переименовать» и «Удалить» — **нет шаринга**.
6. **Тёмная тема не на всех палитрах одинаково читаема.** Цвет точек меню «⋯» подкручивался для контраста, но проверки делались вручную (pitfall §635).
7. **Стрелки ←/→ в фокус-режиме работают, но клавиатурные шорткаты 1-4 для квиза — только если фокус НЕ в input.** Это правильно; но нет визуальной подсказки.
8. **Streak показывается только от 2 дней.** В меню `streak.hidden = true` по умолчанию, что скрывает «0» (можно интерпретировать как отсутствие).
9. **Кнопка `Закрыть` в настройках** — сразу скрывает, но `Esc` тоже закрывает — нет единой подсказки.
10. **CSP в nginx** `script-src 'self' 'unsafe-inline'` — `unsafe-inline` нужен из-за head-script и inline-init (`__ASSET_V`); но это ослабление. Можно вынести inline в `nonce-…`.
11. **`document.startViewTransition` нет в Safari < 18**, fallback применён, но визуально теряется «магия».
12. **Service Worker** есть, но не указано: precaches ли он `/api/*` (только static?). Без `BackgroundSync` API офлайн-edits теряются при смене устройства.
13. **CSRF нет.** Cookie-auth + `SameSite=lax` спасает от типовых атак, но не от всех.
14. **`register` отдаёт `UserResponse` без установки cookies.** После регистрации клиент сам вызывает `login` — два запроса, два коммита, неудобно.

---

## 4. Оценка бизнес-модели

**Бизнес-смысл продукта.** Флэшкарточки для активного вспоминания (active recall). Аудитория — школьники/студенты/изучающие языки. Дифференциатор — эстетика «школьной тетради», русскоязычный фокус, офлайн-capable, шаринг колод.

**Зрелость по чек-листу «бизнес-готовности»:**

| Критерий | Состояние | Комментарий |
|---|---|---|
| Аутентификация | ✅ | Базовая. Нет OAuth, нет верификации email. |
| Модель данных | ✅ | 5 таблиц, миграции, FTS. |
| Публичные колоды | ✅ | Slug-шаринг, есть отдельные endpoint'ы. |
| Многоустройство / синхронизация | ❌ | Односторонняя миграция. Главная блокирующая проблема. |
| Импорт/экспорт | ✅ | JSON+CSV, с защитой от дублей. Но **без картинок**. |
| Аналитика пользователя | ❌ (backend) / ✅ (local) | Сессии пишутся только локально. После миграции — backend «видит» пусто. |
| Email-коммуникация | ❌ | SendGrid подключён, но не используется. |
| Монетизация | ❌ | Не предусмотрена. Модель open-source / self-host. |
| PWA / mobile | ⚠️ | SW есть, viewport-meta есть, брейкпоинты 860/480 есть; «установить как приложение» — нет манифеста `manifest.json`. |
| i18n | ❌ | Строки захардкожены на русском. |
| Observability | ⚠️ | JSON-логирование настроено, но нет prometheus exporter (только ручной `/api/metrics`). |
| Тесты | ⚠️ | Есть, но часть красные. E2E всего 6 штук. |
| CI/CD | ❌ | `.github/workflows/` пусто. |
| Безопасность | ⚠️ | См. §5. |

**Вывод.** Продукт — MVP+, не production-ready. До «production» нужно закрыть:
1. Двухстороннюю синхронизацию (online ↔ offline).
2. CI/CD и реальные тесты (E2E + бэкенд).
3. CSRF и многоузловой rate-limit.
4. Email-верификацию и password reset (если планируется self-signup).
5. Метрики / health-чек в проде.
6. Политику retention данных, GDPR-совместимость.

---

## 5. Безопасность (узкие места)

| Проблема | Где | Риск | Рекомендация (вне рамок этого аудита) |
|---|---|---|---|
| `SECRET_KEY="change-me-in-production"` по умолчанию | `config.py` | Катастрофический при деплое без `.env`. | Проверка при старте, raise при дефолте вне DEBUG. |
| In-memory rate-limit (`defaultdict`) | `middleware.py:8` | Сбрасывается при рестарте; не работает на >1 реплике. | Redis/Sliding window. |
| bcrypt 72-байтный лимит | `services/auth.py:14 hash_password(p[:72])` | Тихое обрезание → DoS-вектор для коллизий. | Перейти на argon2 или явно raise. |
| Нет CSRF при cookie-auth | весь фронт | SameSite=lax спасает от типовых атак, но не от подделанного GET с `text/html`. | Double-submit cookie или token-binding. |
| `register` не верифицирует email | `routers/auth.py` | Спам, throwaway-аккаунты. | Обязательная верификация (нужно поднять `email.py`). |
| `migrate.py` не проверяет владельца payload | `routers/migrate.py` | Любой auth-пользователь может мигрировать ЛЮБЫЕ колоды (свои), но `two_sided=false`, `description` — нет защиты от overwriting. Если payload содержит существующие имена — дубли создаются. | `merge by name` или 409 при конфликте. |
| `share.py` — публичный endpoint возвращает полный deck без rate-limit | `routers/share.py:14` | Скрапинг. | Лимит + кэш. |
| `study_sessions.studied_at` по умолчанию `today()` в Python | `models/__init__.py:79` | Бэкенд пишет дату UTC, фронт пишет локальную; расхождение streak. | Передавать дату с клиента. |
| CORS `"*"` headers + `allow_credentials` | `main.py:39-45` | Если кто-то поставит `*` в `CORS_ORIGINS` — credentials не работают, но поведение тестируется не всеми. | Валидация origin в config. |
| CSP `script-src 'unsafe-inline'` | `nginx.conf:22` | XSS-вектор. | Nonce-based. |
| `email.py` async, вызывается как sync | `services/email.py:7` | Если когда-нибудь вызовут — `RuntimeWarning: coroutine was never awaited`. | `asyncio.run()` или FastAPI `BackgroundTasks`. |
| Media без аутентификации | `nginx.conf:45 /media/` | По `/media/{uuid}.webp` можно брутфорсить чужие картинки. UUID v4 — ок, но slug-картинок нет. | Проверять права на чтение через X-Accel-Redirect. |
| Нет защиты от timing-attack на email-enumeration | `routers/auth.py:31,47` | Разные времена ответов на существующий/несуществующий email. | Унификация по времени. |
| Frontend: `__stylesStale` toast читает `getComputedStyle` синхронно | `app.js:618` | Минимально — OK, но в production полезно логировать в Sentry. | Телеметрия. |

---

## 6. Стабильность и непрерывность (тесты)

**Что падает прямо сейчас** (по `tests/results/failures-2026-08-29.log`):

| Suite | Test | Симптом |
|---|---|---|
| full | `cover-no-scroll` | `sh=522 vh=482` / `sh=527` / `sh=584` — модалка на узком viewport прокручивается фоном. |
| library | `menu-fits`, `menu-fits2` | Меню не помещается в 482px высоты. |
| motion | `M4:pulse-on`, `M4c:pulse-pop` | `scale=0.000` — анимация не запускается. |
| quiz | `menu-open-b` | Меню не открылось. |
| spacing | `menu-open`, `streak-shown`, `streak-text`, `streak-gap -157.7`, `rename-open`, `rename-title-gap 5.5`, `rename-text-field 5.5`, `rename-field-btns 16.6` | Серия streak не показалась; rename-модалка сдвинута; поля слиплись. |
| full | `tour-visible hidden=true`, `tour-arrow-px 50%`, `tour-step1`, `tour-done` | Тур не виден/не переходит. |
| stats-empty | 4 шага | `stats-open`, `empty-visible`, `list-hidden`, `go-study`. |
| filter | (один FAIL без имени), `rows-after-reload 4` | — |

**Корневые причины** (предположения по коду):
- **Viewport в CDP-харнессе** — 480×482/522/527/584. Это **значит, что брейкпоинт 480px активен**, и тесты ломаются на layout для маленьких экранов. Тесты не используют адаптивный viewport.
- **`menu-fits`** — меню на 522px не помещается ⇒ контент обрезан. Скорее всего, высота `.menu-cover` не учитывает safe-area / не скроллится.
- **`pulse-pop scale=0.000`** — JS-анимация `scale 1→1.08` не отрабатывает, потому что `mark.search-hit` отсутствует (или `pulse-marks` снимается слишком рано — pitfall §681).
- **`tour-visible hidden=true`** — тур пытается показать, но `hidden=true` остаётся ⇒ условие показа не срабатывает (видимо, `menuOpen` уже был, `tour` уже прошёл, или hash не `#menu`).
- **`stats-empty`** — модалка статистики не открывается, потому что в headless не зарегистрированы демо-колоды или `localStorage` пуст.
- **`cover-no-scroll`** — фон под модалкой скроллится ⇒ `lockScroll` не вызывается или не работает на mobile-viewport.

**Структурные риски:**
- PowerShell-тесты — это «характерный код», а не unit-тесты. Любая правка разметки ломает 30 сьютов.
- Нет тестов для: study fullscreen transitions, summary-backdrop-z, IDB race-guard, view-transition pixel coords, multi-tab storage sync.
- Нет backend-нагрузочных тестов (concurrent auth, FTS perf).

---

## 7. Исправление оставшихся 9 падений тестов

**Критерий:** 0 failures в 30 сьютах (775 checks).

### Анализ падений

| Тест | Ошибка | Типичная причина |
|------|--------|------------------|
| `full: cover-no-scroll` | `sh=551 vh=482` | `.menu-cover.scrollHeight > viewport` |
| `library: menu-fits` x2 | `sh=484 vh=482` | Меню выше viewport |
| `menu: cover-fits` x2 | `sh=551 ch=442` | Меню выше viewport |
| `pattern: study-patterned` | `none` | Нет фона-паттерна на карточке |
| `pattern: study-unique` | `1` | Ожидается 10 уникальных паттернов |
| `pattern: dark-study` | `false` | Тёмная тема без паттерна |
| `pattern: popup-study-pattern` | `none` | Попап без паттерна |

### Проблема 1: menu-cover не влезает в viewport (6 падений)

**Тест проверяет:** `$(".menu-cover").scrollHeight <= window.innerHeight` (482px в headless Chrome).

**Ошибка подхода:** Я уменьшал padding в `@media (max-height: 520px)`, но тесты запускаются в разных viewport — 482px и 551px+. На desktop (>520px) media query не срабатывает.

**Правильное решение:**
- `.menu-cover` всегда должен иметь `max-height: calc(100vh - 32px)` и `overflow: auto`
- При этом `scrollHeight` всё равно будет > viewport, потому что контент внутри высокий
- Значит тест проверяет что НЕ нужен скролл — т.е. меню должно быть компактным

**Действие:**
1. Найти в CSS селектор `.menu-cover` и установить `max-height: calc(100vh - 20px)`
2. Убедиться что `overflow-y: auto` позволяет внутренний скролл
3. В тесте `cover-no-scroll` — речь идёт о `.menu-cover`, а не о `body`
4. Реальное решение: уменьшить ВСЕ внутренние отступы меню до минимальных, чтобы общая высота контента влезала в 482px

### Проблема 2: pattern suite (4 падения)

**Тест проверяет:** CSS переменные `--study-pattern`, `--study-size`, `--study-pos` применяются к элементам карточки.

**Ошибка:** `study-patterned: ok=false, detail="none"` — значит `getComputedStyle(element).backgroundImage === "none"`.

**Причины:**
- Переменные `--study-pattern` определены в `html[data-palette="..."]` но не применяются к `.face` или `.flashcard-inner`
- Или применяются, но headless Chrome не рендерит CSS-переменные в `getComputedStyle`

**Действие:**
1. Найти в CSS селекторы которые применяют `var(--study-pattern)` — скорее всего `.face::before` или `.flashcard-inner`
2. Проверить что `background-image: var(--study-pattern)` или `background: var(--study-pattern)` указан явно
3. Проверить что `background-size: var(--study-size)` и `background-position: var(--study-pos)` тоже применяются
4. Если переменные определены только в `html[data-palette="..."]` — убедиться что тест загружает страницу с конкретной палитрой

### Порядок выполнения

1. **menu-cover:** установить `max-height: calc(100vh - 20px)` + `overflow-y: auto` в базовых стилях
2. **menu-cover:** уменьшить padding `.menu-backdrop` до `8px 12px 12px` и `.menu-cover` до `6px 12px 6px`
3. **menu-cover:** уменьшить gap/margin внутри секций меню (header, today, actions, theme) на 50%
4. **pattern:** найти селектор `.face::before` или `.flashcard-inner` и добавить явно `background-image: var(--study-pattern)`
5. **pattern:** добавить `background-size: var(--study-size)` и `background-position: var(--study-pos)`
6. **pattern:** проверить тёмную тему — `html[data-mode="dark"]` должен иметь `--study-pattern` определённый

### Валидация

```powershell
powershell -ExecutionPolicy Bypass -File tests\run-tests.ps1 -Parallel 3
```

Ожидаемый результат: 30 suites · pass=775 · fail=0

5. **Подключить VirtualList** для `renderCardRows` при `cards.length > 60`.
6. **Шаринг колоды** — добавить кнопку «Поделиться» в шапку workspace (сейчас только в меню действий).
7. **Синхронизация localStorage ↔ API** (online + offline с очередью): сохранять «грязные» операции и воспроизводить после reconnect.
8. **Backend image upload** — `Data.uploadImage` готов, не вызывается. Использовать вместо (или параллельно с) IndexedDB.
9. **Backend search** — пробросить `search` параметр из UI в `Decks.getCards` (глобальный поиск — отдельная задача).
10. **Global search across decks** (использовать FTS).
11. **PWA manifest.json + иконки 192/512** для «установить как приложение».
12. **Безопасность:**
    - Валидация `SECRET_KEY` при старте.
    - argon2 или явная ошибка для >72 символов.
    - CSRF-token.
    - Использовать `email.py` через `BackgroundTasks` в `register`.
    - Rate-limit на `share` endpoint.

### P2 (polish / long-term)

13. **i18n**: вынести строки UI в один словарь; добавить английскую локаль.
14. **A11y-аудит** на мобильном: проверить `prefers-reduced-motion`, фокус-кольца, размер тач-зон.
15. **Тёмная тема** — проверить контраст на новых палитрах автоматизированно (CDP-зонд уже есть, формализовать).
16. **Манифест-картинки и эмодзи в summary** — заменить эмодзи на SVG, как уже сделано для озвучки.
17. **CSP nonce** вместо `'unsafe-inline'`.
18. **CI** — поднять GitHub Actions с реальными E2E.
19. **Observability** — `/api/metrics` расширить (latency p95, 5xx rate).
20. **Перевод click-outside-анимаций на новый CSS `transition-behavior: allow-discrete`** — меньше JS.
21. **Audit UI-карты id ↔ HTML**: добавить в CI проверку, что все ID из `DOCUMENTATION.md §3.4` присутствуют в `index.html` (есть упоминание «165+ ID», но CI-страж отсутствует).

---

## 8. Реестр файлов проекта (полный по состоянию)

```
backend/
  .env.example
  .gitignore
  alembic.ini
  Dockerfile
  entrypoint.sh
  pyproject.toml
  requirements.txt
  alembic/
    env.py
    versions/0001_initial.py
    versions/0002_add_token_hash_index.py
    versions/0003_add_updated_at_onupdate.py
  app/
    main.py
    config.py
    database.py
    dependencies.py
    middleware.py
    logging_config.py
    models/__init__.py
    routers/
      __init__.py, auth.py, decks.py, cards.py, share.py, study.py, migrate.py
    schemas/
      __init__.py, migration.py
    services/
      __init__.py, auth.py, image.py, email.py, share.py
  tests/
    conftest.py
    test_auth.py, test_decks.py, test_cards.py, test_health.py, test_migrate.py

frontend/
  index.html
  sw.js
  css/style.css
  js/
    api.js
    api/data.js
    app-data.js
    virtual-list.js
    share.js
    router.js
    storage.js
    modal.js
    ui.js
    study.js
    menu.js
    stats.js
    library.js
    data.js
    images.js
    app.js

nginx/
  nginx.conf

scripts/
  backup.sh
  healthcheck.sh

tests/  (30 PowerShell CDP + run-tests.ps1)
tests-e2e/  (3 файла: conftest, test_auth, test_study)

Корень:
  .gitattributes, .gitignore, .kilo/, content/, docker-compose.yml,
  index.html, media/, nginx/, page.html, scripts/, tests/, tests-e2e/,
  CHANGELOG.md, DOCUMENTATION.md, QUICKSTART.md, README.md, screenshot.png
```

---

## 9. Контрольный список для последующих правок (чек-лист «прикоснулся — проверь»)

- [ ] `index.html` — все `?v=N` совпадают (CSS preload, CSS stylesheet, все `<script>`).
- [ ] `index.html` — нет неиспользуемых ID, на которые ссылается JS (`auth-bar`, `auth-user-email`, `auth-logout-btn`, `login-btn`).
- [ ] `style.css` — `.no-anim` переключается в `renderCardRows` (heavy-mode).
- [ ] `style.css` — тени флипа синхронны с WAAPI-кадрами (`translate(6,7)`).
- [ ] `js/app.js` — `verifyStylesFresh` использует актуальный `__ASSET_V`.
- [ ] Backend: `SECRET_KEY` валидируется при старте.
- [ ] Backend: `email.py` либо используется через `BackgroundTasks`, либо удалён.
- [ ] Все красные тесты зелёные до старта новой фичи.
- [ ] При добавлении модалки — используется `showLayer/hideLayer/lockScroll/trapTabKey` из `modal.js`.
- [ ] Новые глобалы — проверены на коллизии имён через поиск по всем js-файлам.
- [ ] Любая правка CSS — подъём `?v=N` + прогон `tests/`.
- [ ] Любая правка бэкенда — `pytest backend/tests` + хотя бы 1 ручной curl.

---

## 10. Что нужно уточнить у пользователя перед реализацией правок

1. **Цель правок.** UX-полировка существующего функционала? Или до-релизная подготовка (security + CI)? Или до-внедрение синхронизации localStorage ↔ API? Это меняет приоритеты в §7.
2. **Поддерживать ли file:// (без бэкенда)?** Сейчас фронт умеет работать офлайн без сервера. Если уходить в «только API», часть кода (library, library-list, demo decks через localStorage) перестанет работать без миграции.
3. **Мобильный-first или desktop-first?** Брейкпоинты 860/480 уже есть, но плотность действий в шапке workspace — desktop-density.
4. **Тёмная тема — оставить две темы или унифицировать?** Палитры × темы — 20 комбинаций. Каждое визуальное изменение требует проверки 20 раз.
5. **Серверный поиск — обязателен?** Если да — план §7.P1.9–10.

Эти пять вопросов блокируют первую итерацию. Без них нельзя сделать карту изменений в файлах.