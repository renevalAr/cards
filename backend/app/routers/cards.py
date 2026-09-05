from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import select
from uuid import UUID

from app.database import get_db
from app.dependencies import get_current_user
from app.models import User, Card, Deck
from app.schemas import CardUpdate, CardReorder, CardResponse

router = APIRouter(prefix="/api/cards", tags=["cards"])


@router.patch("/{card_id}", response_model=CardResponse)
def update_card(
    card_id: UUID,
    data: CardUpdate,
    user: User = Depends(get_current_user),
    db=Depends(get_db),
):
    card = db.get(Card, card_id)
    if not card or card.deck.owner_id != user.id:
        raise HTTPException(status_code=404, detail="Card not found")
    for key, value in data.model_dump(exclude_unset=True).items():
        setattr(card, key, value)
    db.commit()
    db.refresh(card)
    return card


@router.put("/reorder", status_code=status.HTTP_204_NO_CONTENT)
def reorder_cards(
    data: CardReorder,
    user: User = Depends(get_current_user),
    db=Depends(get_db),
):
    cards = db.execute(select(Card).where(Card.id.in_(data.card_ids))).scalars().all()
    if len(cards) != len(data.card_ids):
        raise HTTPException(status_code=400, detail="Some cards were not found")
    deck_id = cards[0].deck_id
    if any(c.deck_id != deck_id for c in cards):
        raise HTTPException(status_code=400, detail="All cards must belong to the same deck")
    deck = db.get(Deck, deck_id)
    if not deck or deck.owner_id != user.id:
        raise HTTPException(status_code=404, detail="Deck not found")
    card_map = {c.id: c for c in cards}
    for idx, card_id in enumerate(data.card_ids):
        card_map[card_id].position = idx
    db.commit()


@router.delete("/{card_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_card(
    card_id: UUID,
    user: User = Depends(get_current_user),
    db=Depends(get_db),
):
    card = db.get(Card, card_id)
    if not card or card.deck.owner_id != user.id:
        raise HTTPException(status_code=404, detail="Card not found")
    db.delete(card)
    db.commit()
