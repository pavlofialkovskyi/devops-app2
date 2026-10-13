"""add users table and messages.user_id column

Revision ID: cb2a8b7b2a19
Revises: 23cb9b7736c8
Create Date: 2026-10-12 00:28:48.564545

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = 'cb2a8b7b2a19'
down_revision: Union[str, Sequence[str], None] = '23cb9b7736c8'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade():
    op.create_table(
        'users',
        sa.Column('id', sa.Integer, primary_key=True),
        sa.Column('email', sa.Text, nullable=False, unique=True),
        sa.Column('password_hash', sa.Text, nullable=False),
        sa.Column('created_at', sa.TIMESTAMP, server_default=sa.func.now(), nullable=False),
    )
    op.add_column('messages', sa.Column('user_id', sa.Integer, nullable=True))
    op.create_foreign_key(
        'fk_messages_user_id', 'messages', 'users',
        ['user_id'], ['id'], ondelete='CASCADE',
    )


def downgrade():
    op.drop_constraint('fk_messages_user_id', 'messages', type_='foreignkey')
    op.drop_column('messages', 'user_id')
    op.drop_table('users')