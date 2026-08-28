from datetime import date, timedelta
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import select, func
from uuid import UUID

from app.database import get_db
from app.dependencies import get_current_user
from app.models import User, Deck, StudySession

router = APIRouter(prefix="/api/study", tags=["study"])


@router.post("/session", status_code=201)
def start_session(deck_id: UUID, user: User = Depends(get_current_user), db=Depends(get_db)):
    deck = db.get(Deck, deck_id)
    if not deck or deck.owner_id != user.id:
        raise HTTPException(status_code=404, detail="Deck not found")
    session = StudySession(user_id=user.id, deck_id=deck_id)
    db.add(session)
    db.commit()
    db.refresh(session)
    return {"id": session.id}


@router.patch("/session/{session_id}")
def update_session(session_id: UUID, known: int = 0, unknown: int = 0, user: User = Depends(get_current_user), db=Depends(get_db)):
    session = db.get(StudySession, session_id)
    if not session or session.user_id != user.id:
        raise HTTPException(status_code=404, detail="Session not found")
    session.known_count = known
    session.unknown_count = unknown
    db.commit()
    return {"id": session.id, "known": known, "unknown": unknown}


@router.get("/stats")
def get_stats(user: User = Depends(get_current_user), db=Depends(get_db)):
    today = date.today()

    today_result = db.execute(
        select(
            func.coalesce(func.sum(StudySession.known_count), 0),
            func.coalesce(func.sum(StudySession.unknown_count), 0),
        ).where(StudySession.user_id == user.id, StudySession.studied_at == today)
    )
    known_today, unknown_today = today_result.first()

    total_result = db.execute(
        select(
            func.coalesce(func.sum(StudySession.known_count), 0),
            func.coalesce(func.sum(StudySession.unknown_count), 0),
        ).where(StudySession.user_id == user.id)
    )
    known_total, unknown_total = total_result.first()

    streak = _compute_streak(user.id, db)

    return {
        "today": {"known": known_today, "unknown": unknown_today},
        "total": {"known": known_total, "unknown": unknown_total},
        "streak": streak,
    }


def _compute_streak(user_id: UUID, db) -> int:
    today = date.today()
    result = db.execute(
        select(StudySession.studied_at).where(
            StudySession.user_id == user_id,
            (StudySession.known_count + StudySession.unknown_count) > 0,
        ).distinct()
    )
    active_days = {row[0] for row in result.fetchall()}

    cursor = today
    if cursor not in active_days:
        cursor -= timedelta(days=1)
        if cursor not in active_days:
            return 0

    streak = 0
    while cursor in active_days:
        streak += 1
        cursor -= timedelta(days=1)
    return streak
