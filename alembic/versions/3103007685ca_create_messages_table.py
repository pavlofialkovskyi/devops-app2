"""create messages table

Revision ID: 3103007685ca
Revises: 
Create Date: 2026-09-17 01:06:57.716766

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = '3103007685ca'
down_revision: Union[str, Sequence[str], None] = None
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade():
    op.create_table(
        'messages',
        sa.Column('id', sa.Integer, primary_key=True, autoincrement=True),
        sa.Column('content', sa.Text, nullable=False),
        sa.Column('image_url', sa.Text, nullable=True),
        sa.Column('created_at', sa.TIMESTAMP, server_default=sa.func.now()),
    )


def downgrade():
    op.drop_table('messages')
