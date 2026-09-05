from pydantic import BaseModel, EmailStr, Field, field_validator, ConfigDict
from uuid import UUID
from datetime import datetime
from typing import Optional
from enum import Enum


class UserCreate(BaseModel):
    email: EmailStr
    password: str = Field(..., min_length=8, max_length=72)

    @field_validator("password")
    @classmethod
    def validate_password_strength(cls, v):
        if not any(c.isupper() for c in v):
            raise ValueError("Password must contain at least one uppercase letter")
        if not any(c.islower() for c in v):
            raise ValueError("Password must contain at least one lowercase letter")
        if not any(c.isdigit() for c in v):
            raise ValueError("Password must contain at least one digit")
        return v


class UserLogin(BaseModel):
    email: EmailStr
    password: str = Field(..., max_length=72)


class UserResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: UUID
    email: str
    display_name: Optional[str]
    is_verified: bool
    created_at: datetime


class TokenResponse(BaseModel):
    access_token: str
    refresh_token: str
    token_type: str = "bearer"


class DeckCreate(BaseModel):
    name: str = Field(..., min_length=1, max_length=200)
    description: Optional[str] = None
    is_public: bool = False
    two_sided: bool = False


class DeckUpdate(BaseModel):
    name: Optional[str] = Field(None, min_length=1, max_length=200)
    description: Optional[str] = None
    is_public: Optional[bool] = None
    two_sided: Optional[bool] = None


class DeckResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: UUID
    name: str
    description: Optional[str]
    is_public: bool
    share_slug: Optional[str]
    two_sided: bool
    cards_count: int
    created_at: datetime
    updated_at: datetime


class CardStatus(str, Enum):
    new = "new"
    known = "known"
    unknown = "unknown"


class CardReorder(BaseModel):
    card_ids: list[UUID] = Field(..., min_length=1)


class CardCreate(BaseModel):
    question: str = Field(..., min_length=1)
    answer: str = Field(..., min_length=1)
    status: CardStatus = CardStatus.new


class CardUpdate(BaseModel):
    question: Optional[str] = Field(None, min_length=1)
    answer: Optional[str] = Field(None, min_length=1)
    status: Optional[CardStatus] = None


class CardResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: UUID
    deck_id: UUID
    question: str
    answer: str
    status: str
    image_path: Optional[str]
    position: int
    created_at: datetime
    updated_at: datetime


class PaginatedResponse(BaseModel):
    items: list
    next_cursor: Optional[str] = None
    total: Optional[int] = None
