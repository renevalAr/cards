import time
from datetime import datetime, timezone
from collections import defaultdict
from fastapi import Request, HTTPException
from starlette.middleware.base import BaseHTTPMiddleware

from app.config import get_settings

RATE_LIMITS = defaultdict(list)
RATE_LIMITS_LAST_CLEANUP = 0
RATE_LIMIT_CLEANUP_INTERVAL = 300  # 5 minutes
RATE_LIMIT_TTL = 600  # 10 minutes


class RateLimitMiddleware(BaseHTTPMiddleware):
    def __init__(self, app, requests_per_minute: int = 5):
        super().__init__(app)
        self.rpm = requests_per_minute
        self.enabled = get_settings().RATE_LIMIT_ENABLED

    async def dispatch(self, request: Request, call_next):
        global RATE_LIMITS_LAST_CLEANUP
        if self.enabled and request.url.path.startswith("/api/auth"):
            now = time.time()

            if now - RATE_LIMITS_LAST_CLEANUP > RATE_LIMIT_CLEANUP_INTERVAL:
                RATE_LIMITS_LAST_CLEANUP = now
                expired = [ip for ip, ts_list in RATE_LIMITS.items() if not ts_list or now - ts_list[-1] > RATE_LIMIT_TTL]
                for ip in expired:
                    del RATE_LIMITS[ip]

            client_ip = request.client.host if request.client else "unknown"
            RATE_LIMITS[client_ip] = [
                t for t in RATE_LIMITS[client_ip] if now - t < 60
            ]

            if len(RATE_LIMITS[client_ip]) >= self.rpm:
                raise HTTPException(
                    status_code=429,
                    detail="Too many requests. Try again later.",
                )

            RATE_LIMITS[client_ip].append(now)

        response = await call_next(request)
        return response


class RequestLoggingMiddleware(BaseHTTPMiddleware):
    async def dispatch(self, request: Request, call_next):
        start = time.time()
        response = await call_next(request)
        duration = time.time() - start

        if duration > 1.0:
            import logging
            logger = logging.getLogger("slow_requests")
            logger.warning(
                f"Slow request: {request.method} {request.url.path} took {duration:.2f}s"
            )

        return response


class SecurityHeadersMiddleware(BaseHTTPMiddleware):
    async def dispatch(self, request: Request, call_next):
        response = await call_next(request)
        response.headers["X-Content-Type-Options"] = "nosniff"
        response.headers["X-Frame-Options"] = "DENY"
        response.headers["X-XSS-Protection"] = "1; mode=block"
        response.headers["Referrer-Policy"] = "strict-origin-when-cross-origin"
        response.headers["Permissions-Policy"] = "camera=(), microphone=(), geolocation=()"
        return response


class SecurityLoggingMiddleware(BaseHTTPMiddleware):
    async def dispatch(self, request: Request, call_next):
        response = await call_next(request)

        if response.status_code in (401, 403, 429):
            import logging
            logger = logging.getLogger("security")
            logger.warning(
                f"Security event: {response.status_code} {request.method} {request.url.path} "
                f"from {request.client.host if request.client else 'unknown'}"
            )

        return response
