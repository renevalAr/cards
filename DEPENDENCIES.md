# Dependencies Map

> Полная карта зависимостей между файлами проекта. Для каждого файла указано: что он ОБЪЯВЛЯЕТ (глобальные объекты/функции) и что он ВЫЗЫВАЕТ из других файлов.

---

## Frontend JS — Load Order & Declarations

Порядок загрузки (index.html, все перед `</body>`):

| # | Файл | Объявляет |
|---|---|---|
| 1 | `js/api.js` | `API`, `Auth`, `Decks`, `Data` |
| 2 | `js/app-data.js` | `AppData` |
| 3 | `js/share.js` | `Share` |
| 4 | `js/router.js` | `Router` |
| 5 | `js/storage.js` | `STORAGE_KEY`, `CORRUPT_KEY`, `MODE_KEY`, `PALETTE_KEY`, `ONBOARD_KEY`, `FONT_KEY`, `VALID_STATUSES`, `MAX_NAME_LENGTH`, `MAX_SESSIONS`, `SCHEMA_VERSION`, `state`, `migrateSchema`, `dateKey`, `todayDateKey`, `resetTodayIfNeeded`, `getTodayStats`, `uid`, `isPlainObject`, `normalizeHistory`, `normalizeSessions`, `normalizeState`, `showToast`, `showStorageAlert`, `loadState`, `isQuotaError`, `saveState`, `selectedDeck`, `cardsInDeck`, `recordStudy`, `recordSession`, `getDeckHistory`, `getAllTimeStats`, `computeStreak` |
| 6 | `js/modal.js` | `getFocusable`, `lockScroll`, `showLayer`, `hideLayer`, `trapTabKey`, `openModal`, `canFocus`, `closeModal`, `openSettingsModal`, `closeSettingsModal`, `closeTopModal`, `bindModalEvents` |
| 7 | `js/ui.js` | `PALETTE_META`, `VALID_PALETTES`, `renderThemeDots`, `makeEl`, `badgeFor`, `cardMatchesFilter`, `filterLabel`, `searchMatches`, `appendHighlighted`, `clearCardSearch`, `renderDeckList`, `renderCardFilters`, `moveCardWithinDeck`, `bindCardRowsDelegation`, `renderCardRows`, `updateCardRowStatus`, `renderStats`, `resetCardForm`, `refreshIndicators`, `render`, `systemDark`, `modePref`, `effectiveMode`, `bindAutoTheme`, `syncAppearanceButtons`, `palettePref`, `fontSizePref`, `applyFontSize`, `syncFontButtons`, `applyAppearance` |
| 8 | `js/study.js` | `scoreStudy`, `bezProgress`, `currentAngle`, `flipHost`, `clearLift`, `killFlipAnims`, `startFlipAnimation`, `shuffle`, `reduceMotion`, `pickRuVoice`, `speakText`, `speakFace`, `stopSpeech`, `entryId`, `entryRev`, `buildStudyEntries`, `beginRound`, `startStudyShuffle`, `resetStudy`, `setStudyMode`, `syncTwoSidedBtn`, `toggleTwoSided`, `enterQuizFocus`, `exitQuizFocus`, `syncStudyView`, `startQuiz`, `beginQuiz`, `enterFocusMode`, `exitFocusMode`, `currentStudyCards`, `setTab`, `syncPressState`, `showStudyCard`, `flipCard`, `isRoundComplete`, `moveStudy`, `markStatus`, `updateQuizMeta`, `buildOptions`, `renderQuizQuestion`, `answerQuiz`, `nextQuiz`, `finishQuiz`, `launchConfetti`, `openSummaryOverlay`, `showSummary`, `closeSummary`, `repeatStudy` |
| 9 | `js/stats.js` | `lastDays`, `countUp`, `openStats`, `closeStats`, `renderDayBars`, `renderStatsWindow`, `openDeckStats`, `closeDeckStats`, `bindStatsEvents` |
| 10 | `js/menu.js` | `pluralDays`, `renderMenu`, `openMenu`, `closeMenu`, `closeAllMenus`, `openMenuPop`, `closeMenuPop`, `renderDeckPicker`, `openDeckPicker`, `closeDeckPicker`, `openDeckActions`, `menuStudy`, `menuOpenCards`, `bigStudy`, `openFirstDeck`, `showTour`, `renderTourStep`, `positionTourTip`, `nextTourStep`, `finishTour`, `hideTour`, `bindMenuEvents` |
| 11 | `js/library.js` | `DEMO_KEY`, `addedDemoIds`, `markDemoAdded`, `DEMO_DECKS`, `renderLibrary`, `openLibrary`, `closeLibrary`, `addDemoDeck` |
| 12 | `js/data.js` | `EXPORT_VERSION`, `todayStamp`, `slugifyName`, `downloadBlob`, `buildBackupPayload`, `exportBaseJson`, `exportDeckJson`, `csvField`, `csvSplitLine`, `exportBaseCsv`, `looksLikeCsv`, `parseImportJson`, `parseImportCsv`, `openDataDialog`, `closeDataDialog`, `summarizeImport`, `handleImportText`, `applyCsvImport`, `applyImport`, `bindDataEvents` |
| 13 | `js/images.js` | `IMG_DB`, `IMG_STORE`, `IMG_MAX_SIDE`, `IMG_QUALITY`, `imgOpen`, `imgTx`, `imgReq`, `imgGet`, `imgPut`, `imgDelete`, `imgGcOrphans`, `loadImageElement`, `compressImageFile` |
| 14 | `js/app.js` | `$`, `$on`, `startEditCard`, `showImagePreview`, `resetImageDraft`, `handleImageFile`, `splitBulkPair`, `parseBulkLines`, `openBulkInput`, `closeBulkInput`, `applyBulkInput`, `createDeck`, `renameDeck`, `deleteDeck`, `resetDeckProgress`, `deleteCard`, `finishDeleteCard`, `saveCard`, `bindEvents`, `bindMotionExtras`, `showAuthModal`, `hideAuthModal`, `showAuthBar`, `bindAuthEvents` |

---

## Frontend JS — Cross-File Calls

### api.js →
- `showToast` (storage.js)

### app-data.js →
- `Decks.*`, `Data.*` (api.js)
- `state`, `saveState` (storage.js)
- `render` (ui.js)
- `showToast` (storage.js)

### share.js →
- `Data.*` (api.js)
- `showToast` (storage.js)

### router.js →
- `showAuthModal` (app.js)
- `Auth` (api.js)
- `menuOpenCards`, `openMenu` (menu.js)
- `Share.viewPublicDeck` (share.js)
- `openStats` (stats.js)
- `openSettingsModal` (modal.js)

### modal.js →
- `syncAppearanceButtons`, `syncFontButtons` (ui.js)
- `closeSummary` (study.js)
- `closeStats` (stats.js)
- `closeDeckPicker`, `closeMenuPop`, `closeMenu` (menu.js)

### ui.js →
- `state`, `cardsInDeck`, `selectedDeck`, `saveState` (storage.js)
- `resetStudy` (study.js)
- `resetCardForm` (app.js)
- `imgGet` (images.js)
- `reduceMotion` (study.js)

### study.js →
- `getTodayStats`, `recordStudy`, `recordSession` (storage.js)
- `state`, `cardsInDeck`, `selectedDeck`, `saveState` (storage.js)
- `renderStats`, `updateCardRowStatus` (ui.js)
- `showLayer`, `hideLayer`, `lockScroll`, `canFocus` (modal.js)

### stats.js →
- `state`, `getTodayStats`, `getAllTimeStats`, `getDeckHistory`, `cardsInDeck`, `dateKey` (storage.js)
- `makeEl` (ui.js)
- `closeMenuPop`, `closeDeckPicker` (menu.js)
- `closeSummary` (study.js)
- `showLayer`, `hideLayer`, `lockScroll`, `trapTabKey`, `canFocus` (modal.js)
- `reduceMotion` (study.js)
- `bigStudy` (menu.js)

### menu.js →
- `getTodayStats`, `computeStreak`, `state`, `cardsInDeck`, `selectedDeck`, `saveState` (storage.js)
- `makeEl` (ui.js)
- `resetStudy`, `startStudyShuffle` (study.js)
- `resetCardForm`, `clearCardSearch` (ui.js/app.js)
- `showLayer`, `hideLayer`, `lockScroll`, `canFocus`, `trapTabKey` (modal.js)
- `applyAppearance` (ui.js)
- `createDeck`, `deleteDeck`, `renameDeck`, `resetDeckProgress` (app.js)
- `exportDeckJson` (data.js)

### library.js →
- `makeEl` (ui.js)
- `state`, `uid`, `saveState`, `resetStudy` (storage.js/study.js)
- `trapTabKey`, `canFocus`, `showLayer`, `hideLayer`, `lockScroll` (modal.js)
- `render` (ui.js)

### data.js →
- `state`, `selectedDeck`, `cardsInDeck`, `saveState`, `uid`, `todayDateKey`, `isPlainObject`, `normalizeState`, `MAX_NAME_LENGTH`, `VALID_STATUSES`, `MAX_SESSIONS` (storage.js)
- `showToast` (storage.js)
- `render` (ui.js)
- `resetStudy` (study.js)
- `closeSettingsModal`, `showLayer`, `hideLayer`, `lockScroll`, `canFocus`, `trapTabKey` (modal.js)

### images.js →
- (standalone, no cross-file calls)

### app.js →
- `API.*`, `Auth.*`, `Decks.*`, `Data.*` (api.js)
- `AppData.*` (app-data.js)
- `state`, `selectedDeck`, `cardsInDeck`, `saveState`, `uid`, `loadState`, `STORAGE_KEY` (storage.js)
- `openModal`, `closeModal`, `showLayer`, `hideLayer`, `lockScroll`, `trapTabKey`, `canFocus`, `bindModalEvents`, `openSettingsModal`, `closeSettingsModal` (modal.js)
- `render`, `renderThemeDots`, `syncAppearanceButtons`, `clearCardSearch`, `resetCardForm`, `refreshIndicators` (ui.js)
- `resetStudy`, `startStudyShuffle`, `reduceMotion`, `showStudyCard`, `flipCard`, `moveStudy`, `markStatus`, `setStudyMode`, `setTab`, `toggleTwoSided`, `startQuiz`, `answerQuiz`, `nextQuiz`, `enterFocusMode`, `exitFocusMode`, `enterQuizFocus`, `exitQuizFocus`, `repeatStudy`, `closeSummary`, `syncStudyView`, `syncTwoSidedBtn`, `speakFace`, `pickRuVoice` (study.js)
- `openStats`, `closeStats` (stats.js)
- `openMenu`, `closeAllMenus` (menu.js)
- `openLibrary`, `closeLibrary` (library.js)
- `imgGet`, `imgPut`, `imgDelete`, `imgGcOrphans`, `compressImageFile` (images.js)
- `bindAutoTheme`, `applyAppearance`, `applyFontSize` (ui.js)
- `bigStudy` (menu.js)
- `handleImportText` (data.js)
- `Router.init` (router.js)

---

## Backend Python — Import Graph

```
config.py
  ↓
database.py
  ↓
models/__init__.py
  ↓
schemas/__init__.py, schemas/migration.py
  ↓
services/auth.py, services/image.py, services/share.py
  ↓
routers/auth.py, routers/decks.py, routers/cards.py, routers/share.py, routers/study.py, routers/migrate.py
  ↓
dependencies.py (get_current_user)
  ↓
middleware.py (RateLimit, Security, Logging)
  ↓
main.py (FastAPI app, routes, lifespan)
```

### No circular imports. Strictly layered.

---

## Cross-Layer: Frontend → Backend

| Frontend Call | Backend Endpoint |
|---|---|
| `Auth.register()` | `POST /api/auth/register` |
| `Auth.login()` | `POST /api/auth/login` |
| `Auth.logout()` | `POST /api/auth/logout` |
| `API._tryRefresh()` | `POST /api/auth/refresh` |
| `Auth.init()` | `GET /api/auth/me` |
| `Decks.list()` | `GET /api/decks` |
| `Decks.get(id)` | `GET /api/decks/{id}` |
| `Decks.create(data)` | `POST /api/decks` |
| `Decks.update(id, data)` | `PATCH /api/decks/{id}` |
| `Decks.delete(id)` | `DELETE /api/decks/{id}` |
| `Decks.getCards(id, ...)` | `GET /api/decks/{id}/cards` |
| `Decks.addCard(id, data)` | `POST /api/decks/{id}/cards` |
| `Data.deleteCard(id)` | `DELETE /api/cards/{id}` |
| `Data.enableShare(deckId)` | `POST /api/decks/{deckId}/share` |
| `Data.disableShare(deckId)` | `DELETE /api/decks/{deckId}/share` |
| `Data.getPublicDeck(slug)` | `GET /api/decks/share/{slug}` |
| `Data.getPublicCards(slug)` | `GET /api/decks/share/{slug}/cards` |
| `Data.migrateData(payload)` | `POST /api/migrate` |

### Orphaned Backend Endpoints (no frontend caller):

| Endpoint | Notes |
|---|---|
| `POST /api/study/session` | Frontend tracks study in localStorage |
| `PATCH /api/study/session/{id}` | Same |
| `GET /api/study/stats` | Same |
| `POST /api/cards/{id}/image` | Frontend uses IndexedDB |
| `DELETE /api/cards/{id}/image` | Same |
| `PATCH /api/cards/{id}` | Card editing is local-only |
| `PUT /api/cards/reorder` | No reorder UI |
| `GET /api/health/detailed` | Infrastructure only |
| `GET /api/metrics` | Infrastructure only |

---

## Dependency Health

| Metric | Value |
|---|---|
| Circular deps (JS) | 0 |
| Circular deps (Python) | 0 |
| Phantom frontend calls | 0 |
| Orphaned backend endpoints | 9 |
| Load-order issues | 0 |
| Dead frontend globals | 0 |
