from pydantic_settings import BaseSettings, SettingsConfigDict
from functools import lru_cache
from typing import List


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", env_file_encoding="utf-8")

    APP_NAME: str = "Flashcards"
    APP_VERSION: str = "2.0.0"
    DEBUG: bool = False

    DATABASE_URL: str = "postgresql://user:pass@db:5432/flashcards"
    SECRET_KEY: str = "change-me-in-production"
    ACCESS_TOKEN_EXPIRE_MINUTES: int = 15
    REFRESH_TOKEN_EXPIRE_DAYS: int = 30

    EMAIL_API_KEY: str = ""
    EMAIL_FROM: str = "no-reply@flashcards.app"

    MEDIA_ROOT: str = "/var/www/media"
    MEDIA_URL: str = "/media"

    CORS_ORIGINS: List[str] = ["http://localhost", "http://localhost:3000"]
    ALLOWED_HOSTS: List[str] = ["localhost", "*.localhost", "testserver"]
    SECURE_COOKIES: bool = False
    RATE_LIMIT_ENABLED: bool = True


@lru_cache
def get_settings() -> Settings:
    return Settings()
