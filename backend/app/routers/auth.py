import itertools
from datetime import datetime, timedelta, timezone
from fastapi import APIRouter, Depends, HTTPException, Request, Response, status
from sqlalchemy import select

from app.config import get_settings
from app.database import get_db
from app.dependencies import get_current_user
from app.models import User, RefreshToken, Deck
from app.schemas import UserCreate, UserLogin, UserResponse, TokenResponse, UserUpdate
from app.services.auth import hash_password, verify_password, create_access_token, create_refresh_token, hash_token, decode_token

settings = get_settings()
_refresh_counter = itertools.count()
_CLEANUP_EVERY = 10


def _set_auth_cookies(response: Response, access_token: str, refresh_token: str):
    response.set_cookie(
        "access_token", access_token,
        httponly=True, samesite="strict", max_age=900,
        secure=settings.SECURE_COOKIES,
    )
    response.set_cookie(
        "refresh_token", refresh_token,
        httponly=True, samesite="strict", max_age=2592000,
        secure=settings.SECURE_COOKIES,
    )

router = APIRouter(prefix="/api/auth", tags=["auth"])


@router.post("/register", response_model=UserResponse, status_code=status.HTTP_201_CREATED)
def register(data: UserCreate, db=Depends(get_db)):
    existing = db.execute(select(User).where(User.email == data.email))
    if existing.scalar_one_or_none():
        raise HTTPException(status_code=409, detail="Email already registered")

    user = User(email=data.email, password_hash=hash_password(data.password))
    db.add(user)
    db.commit()
    db.refresh(user)
    return user


@router.post("/login", response_model=TokenResponse)
def login(data: UserLogin, response: Response, db=Depends(get_db)):
    result = db.execute(select(User).where(User.email == data.email))
    user = result.scalar_one_or_none()

    if not user or not verify_password(data.password, user.password_hash):
        raise HTTPException(status_code=401, detail="Invalid credentials")

    access_token = create_access_token(user.id)
    refresh_token = create_refresh_token(user.id)

    expires_at = datetime.now(timezone.utc) + timedelta(days=settings.REFRESH_TOKEN_EXPIRE_DAYS)
    db_token = RefreshToken(
        user_id=user.id,
        token_hash=hash_token(refresh_token),
        expires_at=expires_at,
    )
    db.add(db_token)
    db.commit()

    _set_auth_cookies(response, access_token, refresh_token)
    return TokenResponse(access_token=access_token, refresh_token=refresh_token)


@router.post("/refresh", response_model=TokenResponse)
def refresh(request: Request, response: Response, db=Depends(get_db)):
    refresh_token = request.cookies.get("refresh_token")
    if not refresh_token:
        raise HTTPException(status_code=401, detail="No refresh token")

    try:
        payload = decode_token(refresh_token)
        if payload.get("type") != "refresh":
            raise HTTPException(status_code=401, detail="Invalid token type")
        user_id = payload["sub"]
    except (ValueError, KeyError):
        raise HTTPException(status_code=401, detail="Invalid refresh token")

    token_hash = hash_token(refresh_token)
    db_token = db.execute(
        select(RefreshToken).where(
            RefreshToken.user_id == user_id,
            RefreshToken.token_hash == token_hash,
        )
    ).scalar_one_or_none()

    if not db_token or db_token.is_revoked:
        raise HTTPException(status_code=401, detail="Refresh token revoked or not found")

    if db_token.expires_at.replace(tzinfo=timezone.utc) < datetime.now(timezone.utc):
        raise HTTPException(status_code=401, detail="Refresh token expired")

    db_token.is_revoked = True

    expired_tokens = db.execute(
        select(RefreshToken).where(
            RefreshToken.user_id == user_id,
            RefreshToken.expires_at < datetime.now(timezone.utc),
        )
    ).scalars().all()
    for expired in expired_tokens:
        db.delete(expired)

    if next(_refresh_counter) % _CLEANUP_EVERY == 0:
        all_expired = db.execute(
            select(RefreshToken).where(
                RefreshToken.expires_at < datetime.now(timezone.utc),
            )
        ).scalars().all()
        for expired in all_expired:
            db.delete(expired)

    user = db.get(User, user_id)
    if not user:
        raise HTTPException(status_code=401, detail="User not found")

    new_access = create_access_token(user.id)
    new_refresh = create_refresh_token(user.id)

    new_expires_at = datetime.now(timezone.utc) + timedelta(days=settings.REFRESH_TOKEN_EXPIRE_DAYS)
    new_db_token = RefreshToken(
        user_id=user.id,
        token_hash=hash_token(new_refresh),
        expires_at=new_expires_at,
    )
    db.add(new_db_token)
    db.commit()

    _set_auth_cookies(response, new_access, new_refresh)
    return TokenResponse(access_token=new_access, refresh_token=new_refresh)


@router.post("/logout")
def logout(request: Request, response: Response, db=Depends(get_db)):
    refresh_token = request.cookies.get("refresh_token")
    if refresh_token:
        token_hash = hash_token(refresh_token)
        db_token = db.execute(
            select(RefreshToken).where(RefreshToken.token_hash == token_hash)
        ).scalar_one_or_none()
        if db_token:
            db_token.is_revoked = True
            try:
                db.commit()
            except Exception:
                db.rollback()

    response.delete_cookie("access_token")
    response.delete_cookie("refresh_token")
    return {"status": "ok"}


@router.get("/me", response_model=UserResponse)
def me(user: User = Depends(get_current_user)):
    return user


@router.patch("/me", response_model=UserResponse)
def update_me(data: UserUpdate, user: User = Depends(get_current_user), db=Depends(get_db)):
    for key, value in data.model_dump(exclude_unset=True).items():
        setattr(user, key, value)
    db.commit()
    db.refresh(user)
    return user


@router.delete("/me", status_code=status.HTTP_200_OK)
def delete_me(user: User = Depends(get_current_user), db=Depends(get_db)):
    tokens = db.execute(select(RefreshToken).where(RefreshToken.user_id == user.id)).scalars().all()
    for token in tokens:
        db.delete(token)
    decks = db.execute(select(Deck).where(Deck.owner_id == user.id)).scalars().all()
    for deck in decks:
        db.delete(deck)
    db.delete(user)
    db.commit()
    return {"status": "ok"}
