from fastapi import APIRouter, Depends, File, HTTPException, UploadFile, status
from uuid import UUID

from app.database import get_db
from app.dependencies import get_current_user
from app.models import User, Deck, Card
from app.schemas import CardUpdate
from app.services.image import validate_image, compress_image, save_image, delete_image

router = APIRouter(prefix="/api/cards", tags=["cards"])


@router.post("/{card_id}/image", status_code=status.HTTP_200_OK)
def upload_card_image(
    card_id: UUID,
    file: UploadFile = File(...),
    user: User = Depends(get_current_user),
    db=Depends(get_db),
):
    card = db.get(Card, card_id)
    if not card or card.deck.owner_id != user.id:
        raise HTTPException(status_code=404, detail="Card not found")

    contents = file.file.read()
    try:
        validate_image(file.content_type, len(contents))
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))

    compressed, ext = compress_image(contents)
    if card.image_path:
        delete_image(card.image_path)

    card.image_path = save_image(card_id, compressed, ext)
    db.commit()
    return {"image_path": card.image_path}


@router.delete("/{card_id}/image", status_code=status.HTTP_204_NO_CONTENT)
def delete_card_image(
    card_id: UUID,
    user: User = Depends(get_current_user),
    db=Depends(get_db),
):
    card = db.get(Card, card_id)
    if not card or card.deck.owner_id != user.id:
        raise HTTPException(status_code=404, detail="Card not found")
    if card.image_path:
        delete_image(card.image_path)
        card.image_path = None
        db.commit()


@router.patch("/{card_id}")
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


@router.delete("/{card_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_card(
    card_id: UUID,
    user: User = Depends(get_current_user),
    db=Depends(get_db),
):
    card = db.get(Card, card_id)
    if not card or card.deck.owner_id != user.id:
        raise HTTPException(status_code=404, detail="Card not found")
    if card.image_path:
        delete_image(card.image_path)
    db.delete(card)
    db.commit()
