"""add email verification

Revision ID: 0005_add_email_verification
Revises: 0004_drop_dead_columns
Create Date: 2026-09-05 00:00:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

revision: str = "0005_add_email_verification"
down_revision: Union[str, None] = "0004_drop_dead_columns"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        "verification_tokens",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column("user_id", postgresql.UUID(as_uuid=True), sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False),
        sa.Column("token_hash", sa.String(255), nullable=False),
        sa.Column("expires_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now()),
    )
    op.create_index("idx_verification_tokens_user", "verification_tokens", ["user_id"])
    op.create_index("idx_verification_tokens_token_hash", "verification_tokens", ["token_hash"])


def downgrade() -> None:
    op.drop_index("idx_verification_tokens_token_hash", table_name="verification_tokens")
    op.drop_index("idx_verification_tokens_user", table_name="verification_tokens")
    op.drop_table("verification_tokens")
