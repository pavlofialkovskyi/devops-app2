"""add media_key, original_filename, and make content nullable

Revision ID: 3b382f45edec
Revises: 3103007685ca
Create Date: 2026-09-26 09:52:35.428253

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = '3b382f45edec'
down_revision: Union[str, Sequence[str], None] = '3103007685ca'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade():
    op.alter_column('messages', 'image_url', new_column_name='media_key')
    op.add_column('messages', sa.Column('original_filename', sa.String(), nullable=True))
    op.alter_column('messages', 'content', nullable=True)


def downgrade():
    op.alter_column('messages', 'content', nullable=False)
    op.drop_column('messages', 'original_filename')
    op.alter_column('messages', 'media_key', new_column_name='image_url')
