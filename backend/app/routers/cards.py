from fastapi import APIRouter, Depends, HTTPException, status
from uuid import UUID

from app.database import get_db
from app.dependencies import get_current_user
from app.models import User, Card
from app.schemas import CardUpdate

router = APIRouter(prefix="/api/cards", tags=["cards"])


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
