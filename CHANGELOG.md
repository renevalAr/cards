# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
- 25 backend tests (pytest) + 6 E2E tests (Playwright)

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
