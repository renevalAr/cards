# Flashcards — Полный запуск

## Быстрый старт (5 минут)

### Вариант 1: Docker (рекомендуется)

```bash
# 1. Клонировать
git clone https://github.com/renevalAr/cards.git
cd cards

# 2. Запустить
docker-compose up -d

# 3. Миграции
docker-compose exec backend alembic upgrade head

# 4. Открыть в браузере
open http://localhost
```

### Вариант 2: Только фронтенд (без сервера)

```bash
# Просто откройте в браузере
open frontend/index.html
# или на Windows: start frontend/index.html
```

Работает в офлайн-режиме через localStorage.

## Деплой на VPS

### Требования
- Ubuntu 22.04/24.04
- Docker + Docker Compose
- Git

### Автоматический деплой
```bash
# На VPS
git clone https://github.com/renevalAr/cards.git
cd cards
chmod +x deploy.sh
./deploy.sh
```

### Ручной деплой
```bash
# 1. Создать .env
cp backend/.env.example backend/.env
# Отредактировать: SECRET_KEY, EMAIL_API_KEY, CORS_ORIGINS

# 2. Запустить
docker-compose up -d --build

# 3. Миграции
docker-compose exec backend alembic upgrade head

# 4. Проверить
curl http://localhost/api/health
```

## Тестирование

### Backend тесты
```bash
docker-compose exec backend pytest tests/ -v
```

### E2E тесты
```bash
docker-compose exec backend pytest tests-e2e/ -v
```

### Frontend smoke-тесты (PowerShell)
```powershell
powershell -ExecutionPolicy Bypass -File tests\run-tests.ps1 -Smoke
```

## Структура проекта

```
flashcards/
├── frontend/          # Клиентское приложение
│   ├── index.html     # Главная страница + auth UI
│   ├── css/           # Стили
│   ├── js/            # Скрипты
│   │   ├── api.js     # API клиент + Auth
│   │   ├── api/       # Data layer
│   │   ├── virtual-list.js
│   │   ├── share.js
│   │   └── ...        # Оригинальные модули
│   └── assets/
├── backend/           # FastAPI сервер
│   ├── app/
│   │   ├── main.py    # Точка входа
│   │   ├── config.py  # Настройки
│   │   ├── database.py
│   │   ├── dependencies.py
│   │   ├── middleware.py
│   │   ├── models/    # SQLAlchemy модели
│   │   ├── schemas/   # Pydantic схемы
│   │   ├── routers/   # API endpoints
│   │   └── services/  # Бизнес-логика
│   ├── alembic/       # Миграции БД
│   ├── tests/         # pytest тесты
│   ├── Dockerfile
│   └── requirements.txt
├── nginx/             # Конфигурация Nginx
├── tests/             # CDP smoke-тесты
├── tests-e2e/         # Playwright E2E
├── docker-compose.yml
├── Makefile
└── deploy.sh
```

## Переменные окружения

| Переменная | По умолчанию | Описание |
|---|---|---|
| `SECRET_KEY` | `change-me-in-production` | Ключ JWT (сгенерировать: `openssl rand -hex 32`) |
| `DATABASE_URL` | `postgresql+asyncpg://flashcards:flashcards@db:5432/flashcards` | Подключение к БД |
| `EMAIL_API_KEY` | `` | SendGrid API ключ |
| `CORS_ORIGINS` | `["http://localhost"]` | Разрешённые origins |
| `ALLOWED_HOSTS` | `["localhost", "*.localhost", "flashcards.app"]` | Trusted hosts |

## Полезные команды

```bash
# Логи
docker-compose logs -f

# База данных
docker-compose exec db psql -U flashcards -d flashcards

# Миграции
docker-compose exec backend alembic revision --autogenerate -m "описание"
docker-compose exec backend alembic upgrade head

# Тесты
docker-compose exec backend pytest tests/ -v

# Остановка
docker-compose down

# Полная очистка
docker-compose down -v --rmi all
```

## После деплоя

1. **SSL**: `sudo certbot --nginx -d your-domain.com`
2. **Firewall**: `sudo ufw allow 80,443/tcp`
3. **Email**: Настроить SendGrid API key в `.env`
4. **Backups**: `docker-compose exec db pg_dump -U flashcards flashcards > backup.sql`
