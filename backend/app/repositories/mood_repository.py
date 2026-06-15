from datetime import date
from uuid import UUID

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.models.domain import utc_now
from app.models.mood import MoodCreate, MoodRecord, MoodUpdate, today


class MoodRepository:
    def __init__(self, session: Session) -> None:
        self.session = session

    def create(self, payload: MoodCreate) -> MoodRecord:
        mood = MoodRecord(
            mood=payload.mood,
            energy=payload.energy,
            notes=payload.notes,
            check_in_date=payload.check_in_date or today(),
        )
        self.session.add(mood)
        self.session.commit()
        self.session.refresh(mood)
        return mood

    def list(
        self,
        *,
        limit: int = 30,
        from_date: date | None = None,
        to_date: date | None = None,
    ) -> list[MoodRecord]:
        statement = select(MoodRecord)
        if from_date is not None:
            statement = statement.where(MoodRecord.check_in_date >= from_date)
        if to_date is not None:
            statement = statement.where(MoodRecord.check_in_date <= to_date)
        statement = statement.order_by(MoodRecord.check_in_date.desc(), MoodRecord.created_at.desc()).limit(limit)
        return list(self.session.scalars(statement).all())

    def get(self, mood_id: UUID) -> MoodRecord | None:
        return self.session.get(MoodRecord, str(mood_id))

    def update(self, mood: MoodRecord, payload: MoodUpdate) -> MoodRecord:
        updates = payload.model_dump(exclude_unset=True)

        for field, value in updates.items():
            setattr(mood, field, value)
        mood.updated_at = utc_now()

        self.session.add(mood)
        self.session.commit()
        self.session.refresh(mood)
        return mood

    def delete(self, mood: MoodRecord) -> None:
        self.session.delete(mood)
        self.session.commit()
