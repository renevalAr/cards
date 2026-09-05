# Flashcards — Полноценное веб-приложение

Архитектурный каркас для трансформации офлайн-прототипа в полноценный веб-сервис.

## Архитектура

```
Nginx (80/443) → FastAPI (uvicorn) → PostgreSQL 16
                ↘ Frontend (Vanilla JS)
                ↘ Media (Local FS)
```

## Технологический стек

| Компонент | Технология |
|---|---|
| Backend | Python 3.12 + FastAPI |
| Database | PostgreSQL 16 + Full-Text Search |
| Auth | JWT (access + refresh tokens) |
| Frontend | Vanilla JS + REST API |
| Поиск | PostgreSQL FTS (tsvector, russian) |
| Тесты | Playwright (Python) |
| Веб-сервер | Nginx + uvicorn |
| Деплой | Docker + Docker Compose + GitHub Actions |

## Структура проекта

```
flashcards/
├── backend/              # FastAPI приложение
│   ├── app/
│   │   ├── main.py       # Точка входа
│   │   ├── config.py     # Настройки (pydantic-settings)
│   │   ├── database.py   # SQLAlchemy sync engine (psycopg2)
│   │   ├── dependencies.py # FastAPI dependencies (auth)
│   │   ├── models/       # SQLAlchemy модели
│   │   ├── schemas/      # Pydantic схемы
│   │   ├── routers/      # API endpoints
│   │   └── services/     # Бизнес-логика
│   ├── alembic/          # Миграции базы данных
│   ├── tests/            # Backend тесты
│   ├── Dockerfile
│   ├── requirements.txt
│   └── pyproject.toml
├── frontend/             # Клиентское приложение
│   ├── index.html
│   ├── js/
│   │   ├── api.js        # API клиент + Auth + Decks + Data
│   │   └── ...
│   ├── css/
├── nginx/                # Конфигурация Nginx
│   ├── nginx.conf
│   └── ssl/
├── tests-e2e/            # Playwright E2E тесты
├── media/                # Загруженные изображения
├── docker-compose.yml
└── .github/workflows/    # CI/CD
    ├── ci.yml
    └── deploy.yml
```

## Быстрый старт

### Локальная разработка

```bash
# 1. Клонировать репозиторий
git clone https://github.com/renevalAr/cards.git
cd cards

# 2. Создать .env файл
cp backend/.env.example backend/.env

# 3. Запустить через Docker Compose
docker-compose up -d

# 4. Применить миграции
cd backend
alembic upgrade head

# 5. Открыть http://localhost
```

### Разработка бэкенда

```bash
cd backend
python -m venv .venv
source .venv/bin/activate  # Windows: .venv\Scripts\activate
pip install -r requirements.txt

# Запуск с горячей перезагрузкой
uvicorn app.main:app --reload
```

### Запуск тестов

```bash
# Backend тесты
cd backend
pytest tests/ -v

# E2E тесты
pip install playwright pytest-playwright
playwright install
pytest tests-e2e/ -v
```

## API Endpoints

### Аутентификация
- `POST /api/auth/register` — Регистрация
- `POST /api/auth/login` — Вход
- `POST /api/auth/refresh` — Обновление токена
- `POST /api/auth/logout` — Выход
- `GET /api/auth/me` — Текущий пользователь
- `PATCH /api/auth/me` — Обновить профиль
- `DELETE /api/auth/me` — Удалить аккаунт

### Колоды
- `GET /api/decks` — Список колод
- `POST /api/decks` — Создать колоду
- `GET /api/decks/{id}` — Получить колоду
- `PATCH /api/decks/{id}` — Обновить колоду
- `DELETE /api/decks/{id}` — Удалить колоду
- `GET /api/decks/{id}/cards` — Карточки (infinite scroll)
- `POST /api/decks/{id}/cards` — Добавить карточку

### Публичные колоды
- `GET /api/decks/share/{slug}` — Публичная колода по ссылке
- `POST /api/decks/{id}/share` — Включить шаринг
- `DELETE /api/decks/{id}/share` — Отключить шаринг

### Карточки
- `PATCH /api/cards/{id}` — Обновить карточку
- `DELETE /api/cards/{id}` — Удалить карточку
- `PUT /api/cards/reorder` — Изменить порядок карточек

### Миграция
- `POST /api/migrate` — Импорт данных из localStorage

### Система
- `GET /api/health` — Healthcheck
- `GET /api/health/detailed` — Детальный healthcheck
- `GET /api/metrics` — Prometheus метрики

## Безопасность

- bcrypt для хеширования паролей
- JWT access (15 мин) + refresh (30 дней) токены
- httpOnly cookies
- CORS с разрешёнными origins
- Rate limiting на auth endpoints
- CSP headers через Nginx

## Лицензия

MIT
