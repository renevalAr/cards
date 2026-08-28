"""add updated_at onupdate trigger

Revision ID: 0003_add_updated_at_onupdate
Revises: 0002_add_token_hash_index
Create Date: 2026-08-28 00:00:00.000000

"""
from typing import Sequence, Union

from alembic import op

revision: str = "0003_add_updated_at_onupdate"
down_revision: Union[str, None] = "0002_add_token_hash_index"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.execute("""
        CREATE OR REPLACE FUNCTION update_modified_column()
        RETURNS TRIGGER AS $$
        BEGIN
            NEW.updated_at = now();
            RETURN NEW;
        END;
        $$ LANGUAGE plpgsql;
    """)

    for table in ["users", "decks", "cards"]:
        op.execute(f"""
            CREATE TRIGGER set_updated_at_{table}
            BEFORE UPDATE ON {table}
            FOR EACH ROW
            EXECUTE FUNCTION update_modified_column();
        """)


def downgrade() -> None:
    for table in ["users", "decks", "cards"]:
        op.execute(f"DROP TRIGGER IF EXISTS set_updated_at_{table} ON {table};")

    op.execute("DROP FUNCTION IF EXISTS update_modified_column();")
