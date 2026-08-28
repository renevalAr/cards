from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import select, func
from uuid import UUID

from app.database import get_db
from app.dependencies import get_current_user
from app.models import User, Deck, Card
from app.schemas import DeckResponse, CardResponse
from app.services.share import generate_share_slug

router = APIRouter(tags=["share"])


@router.get("/api/decks/share/{slug}", response_model=DeckResponse)
def get_public_deck(slug: str, db=Depends(get_db)):
    result = db.execute(select(Deck).where(Deck.share_slug == slug, Deck.is_public == True))
    deck = result.scalar_one_or_none()
    if not deck:
        raise HTTPException(status_code=404, detail="Deck not found or not public")
    count = db.execute(select(func.count(Card.id)).where(Card.deck_id == deck.id)).scalar()
    return DeckResponse(
        id=deck.id,
        name=deck.name,
        description=deck.description,
        is_public=deck.is_public,
        share_slug=deck.share_slug,
        two_sided=deck.two_sided,
        cards_count=count,
        created_at=deck.created_at,
        updated_at=deck.updated_at,
    )


@router.get("/api/decks/share/{slug}/cards", response_model=list[CardResponse])
def get_public_deck_cards(slug: str, db=Depends(get_db)):
    result = db.execute(select(Deck).where(Deck.share_slug == slug, Deck.is_public == True))
    deck = result.scalar_one_or_none()
    if not deck:
        raise HTTPException(status_code=404, detail="Deck not found or not public")

    cards = db.execute(select(Card).where(Card.deck_id == deck.id).order_by(Card.position))
    return [CardResponse.model_validate(c) for c in cards.scalars()]


@router.post("/api/decks/{deck_id}/share", response_model=DeckResponse)
def enable_sharing(deck_id: UUID, user: User = Depends(get_current_user), db=Depends(get_db)):
    deck = db.get(Deck, deck_id)
    if not deck or deck.owner_id != user.id:
        raise HTTPException(status_code=404, detail="Deck not found")
    deck.is_public = True
    if not deck.share_slug:
        deck.share_slug = generate_share_slug()
    db.commit()
    db.refresh(deck)
    count = db.execute(select(func.count(Card.id)).where(Card.deck_id == deck_id)).scalar()
    return DeckResponse(
        id=deck.id,
        name=deck.name,
        description=deck.description,
        is_public=deck.is_public,
        share_slug=deck.share_slug,
        two_sided=deck.two_sided,
        cards_count=count,
        created_at=deck.created_at,
        updated_at=deck.updated_at,
    )


@router.delete("/api/decks/{deck_id}/share", status_code=204)
def disable_sharing(deck_id: UUID, user: User = Depends(get_current_user), db=Depends(get_db)):
    deck = db.get(Deck, deck_id)
    if not deck or deck.owner_id != user.id:
        raise HTTPException(status_code=404, detail="Deck not found")
    deck.is_public = False
    deck.share_slug = None
    db.commit()
