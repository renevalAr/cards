"""add token_hash index

Revision ID: 0002_add_token_hash_index
Revises: 0001_initial
Create Date: 2026-08-28 00:00:00.000000

"""
from typing import Sequence, Union

from alembic import op

revision: str = "0002_add_token_hash_index"
down_revision: Union[str, None] = "0001_initial"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_index("idx_refresh_tokens_token_hash", "refresh_tokens", ["token_hash"])


def downgrade() -> None:
    op.drop_index("idx_refresh_tokens_token_hash", table_name="refresh_tokens")
