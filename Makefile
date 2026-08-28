.PHONY: help build up down logs test test-backend test-e2e migrate shell-db shell-backend clean

help:
	@echo "Available commands:"
	@echo "  make build        - Build Docker images"
	@echo "  make up           - Start all services"
	@echo "  make down         - Stop all services"
	@echo "  make logs         - Show logs"
	@echo "  make test         - Run all tests"
	@echo "  make test-backend - Run backend tests"
	@echo "  make test-e2e     - Run E2E tests"
	@echo "  make migrate      - Run database migrations"
	@echo "  make shell-db     - Open database shell"
	@echo "  make shell-backend- Open backend shell"
	@echo "  make clean        - Remove all containers and volumes"

build:
	docker-compose build

up:
	docker-compose up -d

down:
	docker-compose down

logs:
	docker-compose logs -f

test: test-backend test-e2e

test-backend:
	docker-compose exec backend pytest tests/ -v

test-e2e:
	docker-compose exec backend pytest tests-e2e/ -v

migrate:
	docker-compose exec backend alembic upgrade head

migrate-create:
	docker-compose exec backend alembic revision --autogenerate -m "$(name)"

shell-db:
	docker-compose exec db psql -U flashcards -d flashcards

shell-backend:
	docker-compose exec backend /bin/bash

clean:
	docker-compose down -v --rmi all

lint:
	docker-compose exec backend ruff check app/ tests/

format:
	docker-compose exec backend ruff format app/ tests/

typecheck:
	docker-compose exec backend mypy app/ --ignore-missing-imports

pre-commit: lint format test-backend
