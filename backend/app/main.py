from contextlib import asynccontextmanager
from pathlib import Path
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.middleware.trustedhost import TrustedHostMiddleware
from fastapi.staticfiles import StaticFiles
from fastapi.responses import FileResponse

from app.config import get_settings
from app.routers import auth, decks, share, cards, study, migrate
from app.middleware import RateLimitMiddleware, RequestLoggingMiddleware, SecurityHeadersMiddleware, SecurityLoggingMiddleware
from app.logging_config import setup_logging, get_logger

settings = get_settings()
setup_logging()

FRONTEND_DIR = Path(__file__).resolve().parent.parent / "frontend"

@asynccontextmanager
async def lifespan(app: FastAPI):
    logger = get_logger(__name__)
    logger.info("Application starting up", extra={"version": settings.APP_VERSION})
    yield
    logger.info("Application shutting down")

app = FastAPI(title=settings.APP_NAME, version=settings.APP_VERSION, lifespan=lifespan)

app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.CORS_ORIGINS,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.add_middleware(
    TrustedHostMiddleware,
    allowed_hosts=settings.ALLOWED_HOSTS,
)

app.add_middleware(RateLimitMiddleware, requests_per_minute=5)
app.add_middleware(RequestLoggingMiddleware)
app.add_middleware(SecurityHeadersMiddleware)
app.add_middleware(SecurityLoggingMiddleware)

app.include_router(auth.router)
app.include_router(decks.router)
app.include_router(share.router)
app.include_router(cards.router)
app.include_router(study.router)
app.include_router(migrate.router)

logger = get_logger(__name__)


@app.get("/api/health")
def health():
    return {"status": "ok", "version": settings.APP_VERSION}


@app.get("/api/health/detailed")
def health_detailed():
    from app.database import engine
    from datetime import datetime, timezone
    from sqlalchemy import text

    health = {
        "status": "ok",
        "version": settings.APP_VERSION,
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "checks": {},
    }

    try:
        with engine.connect() as conn:
            conn.execute(text("SELECT 1"))
        health["checks"]["database"] = "ok"
    except Exception as e:
        health["checks"]["database"] = f"error: {str(e)}"
        health["status"] = "degraded"

    return health


@app.get("/api/metrics")
def metrics():
    from app.database import engine
    from sqlalchemy import text, func
    from app.models import User, Deck, Card

    stats = {}
    try:
        with engine.connect() as conn:
            stats["users_total"] = conn.execute(text("SELECT COUNT(*) FROM users")).scalar()
            stats["decks_total"] = conn.execute(text("SELECT COUNT(*) FROM decks")).scalar()
            stats["cards_total"] = conn.execute(text("SELECT COUNT(*) FROM cards")).scalar()
            stats["public_decks"] = conn.execute(
                text("SELECT COUNT(*) FROM decks WHERE is_public = true")
            ).scalar()
    except Exception:
        pass

    lines = []
    for key, value in stats.items():
        lines.append(f"flashcards_{key} {value}")

    return "\n".join(lines)


if FRONTEND_DIR.exists():
    app.mount("/css", StaticFiles(directory=str(FRONTEND_DIR / "css")), name="css")
    app.mount("/js", StaticFiles(directory=str(FRONTEND_DIR / "js")), name="js")

    @app.get("/sw.js")
    def service_worker():
        return FileResponse(str(FRONTEND_DIR / "sw.js"), media_type="application/javascript")

    @app.get("/")
    def index():
        return FileResponse(str(FRONTEND_DIR / "index.html"))

    @app.get("/d/{slug}")
    def shared_deck(slug: str):
        return FileResponse(str(FRONTEND_DIR / "index.html"))
