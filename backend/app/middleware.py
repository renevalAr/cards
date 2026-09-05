import time
from datetime import datetime, timezone
from collections import defaultdict
from fastapi import Request, HTTPException
from fastapi.responses import JSONResponse
from starlette.middleware.base import BaseHTTPMiddleware

from app.config import get_settings

RATE_LIMITS = defaultdict(list)
RATE_LIMITS_LAST_CLEANUP = 0
RATE_LIMIT_CLEANUP_INTERVAL = 300  # 5 minutes
RATE_LIMIT_TTL = 600  # 10 minutes


# Per-endpoint rate-limit budgets (requests-per-minute). Applied AFTER nginx.
# These are intentionally generous since nginx is the first line of defense;
# this catches abusive clients that bypass the proxy or hit the backend directly.
RATE_BUDGETS_RPM = {
    "/api/auth/register": 30,
    "/api/auth/login": 30,
    "/api/auth/refresh": 60,
    "/api/auth/me": 120,
    "/api/auth/logout": 60,
    "/api/auth/verify-request": 30,
    "/api/auth/verify": 60,
}


def _resolve_budget(path: str, default_api_rpm: int) -> int:
    """Return the per-minute budget for a path, supporting trailing-slash + query-string."""
    if path in RATE_BUDGETS_RPM:
        return RATE_BUDGETS_RPM[path]
    # Strip query string and trailing slash
    base = path.rstrip("/")
    return RATE_BUDGETS_RPM.get(base, default_api_rpm)


def _client_ip(request: Request) -> str:
    return (
        request.headers.get("X-Forwarded-For", "").split(",")[0].strip()
        or request.headers.get("X-Real-IP", "")
        or (request.client.host if request.client else "unknown")
    )


class RateLimitMiddleware(BaseHTTPMiddleware):
    def __init__(self, app, auth_rpm: int = 60, api_rpm: int = 120):
        super().__init__(app)
        # auth_rpm is used as the fallback for /api/auth/* paths not explicitly budgeted.
        self.auth_rpm = auth_rpm
        self.api_rpm = api_rpm
        self.enabled = get_settings().RATE_LIMIT_ENABLED

    async def dispatch(self, request: Request, call_next):
        global RATE_LIMITS_LAST_CLEANUP
        path = request.url.path
        if self.enabled and path.startswith("/api/"):
            now = time.time()

            if now - RATE_LIMITS_LAST_CLEANUP > RATE_LIMIT_CLEANUP_INTERVAL:
                RATE_LIMITS_LAST_CLEANUP = now
                expired = [ip for ip, ts_list in RATE_LIMITS.items() if not ts_list or now - ts_list[-1] > RATE_LIMIT_TTL]
                for ip in expired:
                    del RATE_LIMITS[ip]

            client_ip = _client_ip(request)
            if path.startswith("/api/auth"):
                limit = _resolve_budget(path, self.auth_rpm)
            else:
                limit = self.api_rpm

            RATE_LIMITS[client_ip] = [
                t for t in RATE_LIMITS[client_ip] if now - t < 60
            ]

            if len(RATE_LIMITS[client_ip]) >= limit:
                # Return JSONResponse directly to avoid BaseHTTPMiddleware
                # logging the HTTPException as a 500 error.
                return JSONResponse(
                    status_code=429,
                    content={"detail": "Too many requests. Try again later."},
                    headers={"Retry-After": "60"},
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
                f"from {request.headers.get('X-Forwarded-For', '').split(',')[0].strip() or request.headers.get('X-Real-IP', '') or (request.client.host if request.client else 'unknown')}"
            )

        return response
