from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy import select, func
from uuid import UUID

from app.database import get_db
from app.dependencies import get_current_user
from app.models import User, Deck, Card
from app.schemas import DeckCreate, DeckUpdate, DeckResponse, CardCreate, CardResponse, PaginatedResponse

router = APIRouter(prefix="/api/decks", tags=["decks"])


def deck_to_response(deck: Deck, cards_count: int = None) -> DeckResponse:
    return DeckResponse(
        id=deck.id,
        name=deck.name,
        description=deck.description,
        is_public=deck.is_public,
        share_slug=deck.share_slug,
        two_sided=deck.two_sided,
        cards_count=cards_count if cards_count is not None else len(deck.cards),
        created_at=deck.created_at,
        updated_at=deck.updated_at,
    )


@router.get("", response_model=list[DeckResponse])
def list_decks(user: User = Depends(get_current_user), db=Depends(get_db)):
    result = db.execute(select(Deck).where(Deck.owner_id == user.id).order_by(Deck.updated_at.desc()))
    decks = result.scalars().all()
    deck_ids = [d.id for d in decks]
    counts = dict(db.execute(
        select(Card.deck_id, func.count(Card.id)).where(Card.deck_id.in_(deck_ids)).group_by(Card.deck_id)
    ).all())
    return [deck_to_response(d, cards_count=counts.get(d.id, 0)) for d in decks]


@router.post("", response_model=DeckResponse, status_code=201)
def create_deck(data: DeckCreate, user: User = Depends(get_current_user), db=Depends(get_db)):
    deck = Deck(owner_id=user.id, **data.model_dump())
    db.add(deck)
    db.commit()
    db.refresh(deck)
    return deck_to_response(deck, cards_count=0)


@router.get("/{deck_id}", response_model=DeckResponse)
def get_deck(deck_id: UUID, user: User = Depends(get_current_user), db=Depends(get_db)):
    deck = db.get(Deck, deck_id)
    if not deck or deck.owner_id != user.id:
        raise HTTPException(status_code=404, detail="Deck not found")
    count = db.execute(select(func.count(Card.id)).where(Card.deck_id == deck_id)).scalar()
    return deck_to_response(deck, cards_count=count)


@router.patch("/{deck_id}", response_model=DeckResponse)
def update_deck(deck_id: UUID, data: DeckUpdate, user: User = Depends(get_current_user), db=Depends(get_db)):
    deck = db.get(Deck, deck_id)
    if not deck or deck.owner_id != user.id:
        raise HTTPException(status_code=404, detail="Deck not found")
    for key, value in data.model_dump(exclude_unset=True).items():
        setattr(deck, key, value)
    db.commit()
    db.refresh(deck)
    count = db.execute(select(func.count(Card.id)).where(Card.deck_id == deck_id)).scalar()
    return deck_to_response(deck, cards_count=count)


@router.delete("/{deck_id}", status_code=204)
def delete_deck(deck_id: UUID, user: User = Depends(get_current_user), db=Depends(get_db)):
    deck = db.get(Deck, deck_id)
    if not deck or deck.owner_id != user.id:
        raise HTTPException(status_code=404, detail="Deck not found")
    db.delete(deck)
    db.commit()


@router.get("/{deck_id}/cards", response_model=PaginatedResponse)
def list_cards(
    deck_id: UUID,
    cursor: str = Query(None),
    limit: int = Query(30, ge=1, le=100),
    search: str = Query(None),
    user: User = Depends(get_current_user),
    db=Depends(get_db),
):
    deck = db.get(Deck, deck_id)
    if not deck or deck.owner_id != user.id:
        raise HTTPException(status_code=404, detail="Deck not found")

    query = select(Card).where(Card.deck_id == deck_id)
    if search:
        query = query.where(
            func.to_tsvector("russian", Card.question + " " + Card.answer).op("@@")(
                func.plainto_tsquery("russian", search)
            )
        )
    if cursor:
        try:
            cursor_pos = int(cursor)
        except ValueError:
            raise HTTPException(status_code=status.HTTP_422_UNPROCESSABLE_ENTITY, detail="Invalid cursor value")
        query = query.where(Card.position > cursor_pos)

    query = query.order_by(Card.position).limit(limit + 1)
    result = db.execute(query)
    cards = result.scalars().all()

    next_cursor = None
    if len(cards) > limit:
        next_cursor = str(cards[-1].position)
        cards = cards[:limit]

    return PaginatedResponse(
        items=[CardResponse.model_validate(c) for c in cards],
        next_cursor=next_cursor,
    )


@router.post("/{deck_id}/cards", response_model=CardResponse, status_code=201)
def create_card(deck_id: UUID, data: CardCreate, user: User = Depends(get_current_user), db=Depends(get_db)):
    deck = db.get(Deck, deck_id)
    if not deck or deck.owner_id != user.id:
        raise HTTPException(status_code=404, detail="Deck not found")

    max_pos = db.execute(select(func.max(Card.position)).where(Card.deck_id == deck_id))
    next_pos = (max_pos.scalar() or 0) + 1

    card = Card(deck_id=deck_id, position=next_pos, **data.model_dump())
    db.add(card)
    db.commit()
    db.refresh(card)
    return card
