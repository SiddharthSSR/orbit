from uuid import UUID

from sqlalchemy import delete, select
from sqlalchemy.orm import Session

from app.core.time import utc_now
from app.models.chat import ChatMessageRecord, ChatRole, ChatSessionCreate, ChatSessionRecord


class ChatRepository:
    def __init__(self, session: Session) -> None:
        self.session = session

    def create_session(self, payload: ChatSessionCreate) -> ChatSessionRecord:
        chat_session = ChatSessionRecord(title=payload.title)
        self.session.add(chat_session)
        self.session.commit()
        self.session.refresh(chat_session)
        return chat_session

    def get_session(self, session_id: UUID) -> ChatSessionRecord | None:
        return self.session.get(ChatSessionRecord, str(session_id))

    def list_sessions(self) -> list[ChatSessionRecord]:
        statement = select(ChatSessionRecord).order_by(ChatSessionRecord.updated_at.desc())
        return list(self.session.scalars(statement).all())

    def create_message(
        self,
        *,
        session_id: UUID | str,
        role: ChatRole,
        content: str,
    ) -> ChatMessageRecord:
        message = ChatMessageRecord(
            session_id=str(session_id),
            role=role,
            content=content,
        )
        chat_session = self.session.get(ChatSessionRecord, str(session_id))
        if chat_session is not None:
            chat_session.updated_at = utc_now()
            self.session.add(chat_session)
        self.session.add(message)
        self.session.commit()
        self.session.refresh(message)
        return message

    def delete_session(self, chat_session: ChatSessionRecord) -> None:
        self.session.execute(
            delete(ChatMessageRecord).where(ChatMessageRecord.session_id == chat_session.id)
        )
        self.session.delete(chat_session)
        self.session.commit()

    def list_messages_for_session(self, session_id: UUID, *, limit: int | None = None) -> list[ChatMessageRecord]:
        statement = (
            select(ChatMessageRecord)
            .where(ChatMessageRecord.session_id == str(session_id))
            .order_by(ChatMessageRecord.created_at.asc())
        )
        if limit is not None:
            statement = statement.limit(limit)
        return list(self.session.scalars(statement).all())

    def list_recent_messages_for_session(
        self,
        session_id: UUID | str,
        *,
        limit: int,
    ) -> list[ChatMessageRecord]:
        statement = (
            select(ChatMessageRecord)
            .where(ChatMessageRecord.session_id == str(session_id))
            .order_by(ChatMessageRecord.created_at.desc())
            .limit(limit)
        )
        return list(reversed(self.session.scalars(statement).all()))
