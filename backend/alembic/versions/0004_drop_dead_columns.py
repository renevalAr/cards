"""drop dead columns and tables

Revision ID: 0004_drop_dead_columns
Revises: 0003_add_updated_at_onupdate
Create Date: 2026-09-05 00:00:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa

revision: str = "0004_drop_dead_columns"
down_revision: Union[str, None] = "0003_add_updated_at_onupdate"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.execute("DROP INDEX IF EXISTS idx_decks_fts")
    op.execute("DROP INDEX IF EXISTS idx_cards_fts")

    op.drop_column("decks", "search_vector")
    op.drop_column("cards", "search_vector")
    op.drop_column("cards", "image_path")

    op.drop_table("study_sessions")

    op.create_index("idx_cards_deck_position", "cards", ["deck_id", "position"])


def downgrade() -> None:
    op.drop_index("idx_cards_deck_position", table_name="cards")

    op.create_table(
        "study_sessions",
        sa.Column("id", sa.dialects.postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column("user_id", sa.dialects.postgresql.UUID(as_uuid=True), sa.ForeignKey("users.id", ondelete="CASCADE"), index=True),
        sa.Column("deck_id", sa.dialects.postgresql.UUID(as_uuid=True), sa.ForeignKey("decks.id", ondelete="CASCADE"), index=True),
        sa.Column("known_count", sa.Integer, server_default="0"),
        sa.Column("unknown_count", sa.Integer, server_default="0"),
        sa.Column("studied_at", sa.Date, index=True),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now()),
    )

    op.add_column("cards", sa.Column("image_path", sa.String(500), nullable=True))
    op.add_column("cards", sa.Column("search_vector", sa.Text, nullable=True))
    op.add_column("decks", sa.Column("search_vector", sa.Text, nullable=True))
