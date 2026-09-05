import uuid
import secrets
import hashlib
from datetime import datetime, timedelta, timezone
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.models import VerificationToken


def generate_verification_token(db: Session, user_id: uuid.UUID, expires_minutes: int = 1440) -> str:
    """Generate a verification token for the user. Returns the raw token (to be sent via email)."""
    raw_token = secrets.token_urlsafe(32)
    token_hash = hashlib.sha256(raw_token.encode()).hexdigest()
    expires_at = datetime.now(timezone.utc) + timedelta(minutes=expires_minutes)

    # Invalidate any existing tokens for this user
    existing = db.execute(
        select(VerificationToken).where(VerificationToken.user_id == user_id)
    ).scalars().all()
    for t in existing:
        db.delete(t)

    db_token = VerificationToken(
        user_id=user_id,
        token_hash=token_hash,
        expires_at=expires_at,
    )
    db.add(db_token)
    db.commit()

    return raw_token


def verify_token(db: Session, raw_token: str) -> uuid.UUID | None:
    """Verify a token. Returns user_id if valid, None if invalid/expired."""
    token_hash = hashlib.sha256(raw_token.encode()).hexdigest()

    db_token = db.execute(
        select(VerificationToken).where(
            VerificationToken.token_hash == token_hash,
        )
    ).scalar_one_or_none()

    if not db_token:
        return None

    if db_token.expires_at.replace(tzinfo=timezone.utc) < datetime.now(timezone.utc):
        db.delete(db_token)
        db.commit()
        return None

    user_id = db_token.user_id
    db.delete(db_token)
    db.commit()

    return user_id
