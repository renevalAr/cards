# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [2.3.0] - 2026-09-05

### Removed
- Deleted `routers/study.py` — 3 orphaned study session endpoints (frontend uses localStorage)
- Deleted `services/image.py` — unused server-side image handling (frontend uses IndexedDB)
- Deleted `tests/test_study_api.py` — tests for removed study endpoints
- Removed card image endpoints (`POST/DELETE /api/cards/{id}/image`)
- Removed card update endpoint (`PATCH /api/cards/{id}`)
- Removed card reorder endpoint (`PUT /api/cards/reorder`)
- Removed unused model fields: `Card.image_path`, `Card.search_vector`, `Deck.search_vector`
- Removed unused schemas: `CardReorder`
- Removed unused config: `EMAIL_API_KEY`, `EMAIL_FROM`
- Removed dead frontend functions: `Decks.get()`, `Decks.update()`, `AppData.isSyncing()`, `AppData.getError()`, `Router.navigate()`, `Router.getCurrentRoute()`, `Router.getCurrentParams()`
- Removed dead CSS classes: `.auth-user`, `.scroll-sentinel`, `.list-loader`, `.list-end`

### Security
- Share slug now uses `secrets.token_urlsafe(12)` (72+ bits entropy) instead of UUID[:8] (32 bits)
- Cookie `SameSite` changed from `lax` to `strict` for CSRF protection
- Migration endpoint now limited to max 50 decks, 500 cards per deck, 5000 chars per field
- Card create/update now limited to max 5000 chars per field
- `health/detailed` no longer leaks DB error messages
- Rate limiter now evicts stale entries every 5 minutes (prevents memory leak)

### Fixed
- `RateLimitMiddleware` now uses `settings.RATE_LIMIT_ENABLED` instead of `os.getenv()`
- `main.py` now imports `Depends` from FastAPI (was missing)

### Performance
- `saveState()` now debounced at 200ms (batches rapid mutations)
- Refresh token cleanup on refresh (removes expired tokens for user)

### Documentation
- Updated API docs: removed 7 dead endpoints
- Updated model schema: removed `image_path`, `search_vector`
- Updated test count: 38 backend tests
- Updated DEPENDENCIES.md: removed deleted files

---

## [2.2.0] - 2026-09-05

### Fixed
- Fixed `typeof raw.deck` bug in import parser (TypeError on malformed deck files)
- Fixed `imgOpen` permanent failure state (IndexedDB operations no longer die forever on error)
- Fixed hardcoded `STORAGE_KEY` in `Data.exportLocalData()` export
- Fixed `positionTourTip` null dereference when tour target element not found
- Fixed `aria-labelledby="auth-title"` referencing non-existent element in auth modal
- Fixed duplicate `.menu-backdrop` CSS block
- Added `:focus-visible` outline for dialog elements (accessibility)
- Added `aria-label` to SVG-only buttons (workspace login, share, menu login)

### Added
- Corrupt payload backup to `flashcards-app-v1-corrupt` key + warn-toast on parse failure
- Session merge sort by date before cap (fresh local sessions not evicted by old imports)
- `imgGcOrphans` — garbage collection of orphaned IndexedDB images on startup
- `MAX_SESSIONS` constant (200) in storage.js + data.js
- `CORRUPT_KEY` constant for corrupt payload backup
- `FONT_KEY` constant documented
- Missing API endpoints documented in README (cards, study, migrate, health)
- `app-data.js` and `router.js` added to documentation file structure
- Function Map updated with 15+ missing functions
- DOM Contract updated with missing IDs
- Z-index scale corrected and completed
- Backend test paths corrected (`backend/tests/`)
- E2E test count corrected (10, not 6)
- Smoke test check count corrected (758, not ~769)
- Environment variable defaults corrected in QUICKSTART.md

### Changed
- Asset versions bumped to v=41

## [2.1.0] - 2026-08-29

### Fixed
- Fixed `?v=` cache-busting consistency in index.html (preload and stylesheet now use same version)
- Restored missing auth-bar HTML nodes (`auth-bar`, `auth-user-email`, `auth-logout-btn`, `login-btn`) for proper auth UI
- Fixed auth UX: added visible "Войти/Выйти" menu item and fixed auth bar display logic
- Fixed heavy-mode for large card lists (>60 rows): animation delay only applied to first 18 rows, `.no-anim` class properly toggled
- Fixed `cover-no-scroll` test failure: enhanced `lockScroll` with `touch-action: none`, `overscroll-behavior: contain`, and `position: fixed` fallback for iOS Safari; also blocks scroll on `.main` and `.sidebar`
- Fixed `menu-fits` test failure: added `max-height: calc(100vh - 32px)` and `overflow: auto` to `.menu-cover` for internal scrolling on small viewports
- Fixed `pulse-pop` animation test: increased `pulse-marks` removal timeout from 1200ms to 1400ms to ensure animation completes
- Fixed tour visibility: made `showTour` more robust by checking `tourStep > -1` instead of `!== -1`, added null checks
- Fixed streak display: now shows streak count from day 1 (previously hidden until day 2), with "Начни серию" prompt when streak is 0
- Fixed stats-empty test: corrected script load order - `stats.js` now loads before `menu.js` so `openStats` is available when menu binds events
- Fixed SECRET_KEY validation: backend now raises RuntimeError on startup if default SECRET_KEY is used in production

### Added
- Share button (⤴) in workspace header for quick deck sharing (enable sharing + copy link in one click)
- `flame-dim` SVG style for zero-streak state

### Changed
- Reordered script loading in index.html: `stats.js` before `menu.js` to ensure `openStats` is defined at bind time
- Streak now visible at 1+ days (was 2+) with different messaging for 0 streak

### Security
- SECRET_KEY validation at startup prevents deployment with default key

---

## [2.0.0] - 2026-08-28

### Added
- Backend API with FastAPI + SQLAlchemy + PostgreSQL 16
- JWT authentication (access 15min + refresh 30 days) via httpOnly cookies
- Full-text search with PostgreSQL FTS (Russian language)
- Deck sharing via public slug URLs
- Study sessions and statistics tracking
- Data migration endpoint (localStorage → PostgreSQL)
- Image upload with Pillow compression (480px, WebP)
- Password strength validation (uppercase, lowercase, digit required)
- Security headers middleware (X-Content-Type-Options, X-Frame-Options, etc.)
- Security logging for 401/403/429 events
- Rate limiting on auth endpoints (5 req/min)
- Hash-based frontend routing
- Frontend data synchronization with API
- Migration UI button (localStorage → server)
- Network error handling in API client
- Alembic database migrations
- Docker Compose orchestration (Nginx + FastAPI + PostgreSQL)
- CI/CD with GitHub Actions
- 25 backend tests (pytest) + 10 E2E tests (Playwright)

### Fixed
- `/refresh` endpoint now correctly reads cookies from Request object
- `ALLOWED_HOSTS` restricted to specific domains (removed `*`)
- `decode_token` now catches `ExpiredSignatureError` separately
- N+1 query issues in deck serialization (separate count queries)
- `__dict__` serialization replaced with Pydantic `model_validate`
- `alembic/env.py` rewritten for sync engine (psycopg2)
- `updated_at` field now auto-updates via database trigger
- Added index on `refresh_tokens.token_hash` for faster lookups
- Pydantic V2 deprecation warnings fixed (`model_config = ConfigDict(...)`)
- FastAPI `on_event` replaced with `lifespan` context manager

### Changed
- Migrated from async SQLAlchemy to sync (psycopg2) for compatibility
- Frontend now loads data from API after authentication
- Password minimum length is 8 characters with complexity requirements

### Security
- Cookies now use `httponly`, `samesite=lax`, and `secure` (configurable)
- TrustedHostMiddleware enabled with specific allowed hosts
- Security headers added to all responses
- Suspicious activity logging (401, 403, 429)

---

## [1.0.0] - 2026-08-27

### Initial Release
- Offline-first flashcard application
- Vanilla HTML/CSS/JS (no frameworks/build)
- localStorage persistence
- 10 color palettes with light/dark themes
- Flip and quiz study modes
- Fullscreen focus mode
- Text-to-speech (Russian voices)
- Import/export (JSON, CSV)
- Image support with IndexedDB storage
- Bulk card input
- Statistics and streak tracking
- Onboarding tour
- 30 PowerShell CDP smoke tests (~769 checks)
