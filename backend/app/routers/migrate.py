from fastapi import APIRouter, Depends, HTTPException

from app.database import get_db
from app.dependencies import get_current_user
from app.models import User, Deck, Card
from app.schemas.migration import MigrationPayload

router = APIRouter(prefix="/api/migrate", tags=["migrate"])


@router.post("", status_code=201)
def migrate_data(payload: MigrationPayload, user: User = Depends(get_current_user), db=Depends(get_db)):
    if not payload.decks:
        raise HTTPException(status_code=400, detail="No decks to migrate")

    migrated = []
    for deck_data in payload.decks:
        deck = Deck(
            owner_id=user.id,
            name=deck_data.name,
            description=deck_data.description,
            two_sided=deck_data.two_sided,
        )
        db.add(deck)
        db.flush()

        for idx, card_data in enumerate(deck_data.cards):
            card = Card(
                deck_id=deck.id,
                question=card_data.question,
                answer=card_data.answer,
                status=card_data.status if card_data.status in ("new", "known", "unknown") else "new",
                position=idx + 1,
            )
            db.add(card)

        migrated.append({"id": str(deck.id), "name": deck.name, "cards_count": len(deck_data.cards)})

    db.commit()
    return {"migrated": migrated, "total_decks": len(migrated)}
