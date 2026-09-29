"""make created_at not null

Revision ID: 23cb9b7736c8
Revises: 3b382f45edec
Create Date: 2026-09-27 16:32:42.072389

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = '23cb9b7736c8'
down_revision: Union[str, Sequence[str], None] = '3b382f45edec'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade():
    op.execute("UPDATE messages SET created_at = now() WHERE created_at IS NULL")
    op.alter_column('messages', 'created_at', nullable=False)


def downgrade():
     op.alter_column('messages', 'created_at', nullable=True)
