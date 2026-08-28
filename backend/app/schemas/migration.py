from pydantic import BaseModel, Field
from typing import Optional


class MigrationDeck(BaseModel):
    name: str = Field(..., min_length=1, max_length=200)
    description: Optional[str] = None
    two_sided: bool = False
    cards: list["MigrationCard"] = []


class MigrationCard(BaseModel):
    question: str = Field(..., min_length=1)
    answer: str = Field(..., min_length=1)
    status: str = "new"


class MigrationPayload(BaseModel):
    version: str = "migration-v1"
    exported_at: Optional[str] = None
    decks: list[MigrationDeck] = []
