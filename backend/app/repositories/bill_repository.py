from uuid import UUID

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.models.bill import BillCreate, BillRecord, BillUpdate
from app.core.time import utc_now


class BillRepository:
    def __init__(self, session: Session) -> None:
        self.session = session

    def create(self, payload: BillCreate) -> BillRecord:
        bill = BillRecord(
            name=payload.name,
            amount=payload.amount,
            currency=payload.currency,
            due_date=payload.due_date,
            recurrence=payload.recurrence,
            is_paid=payload.is_paid,
            reminder_days_before=payload.reminder_days_before,
            notes=payload.notes,
        )
        self.session.add(bill)
        self.session.commit()
        self.session.refresh(bill)
        return bill

    def list(self) -> list[BillRecord]:
        statement = select(BillRecord).order_by(
            BillRecord.is_paid.asc(),
            BillRecord.due_date.asc(),
            BillRecord.created_at.desc(),
        )
        return list(self.session.scalars(statement).all())

    def get(self, bill_id: UUID) -> BillRecord | None:
        return self.session.get(BillRecord, str(bill_id))

    def update(self, bill: BillRecord, payload: BillUpdate) -> BillRecord:
        updates = payload.model_dump(exclude_unset=True)

        for field, value in updates.items():
            setattr(bill, field, value)
        bill.updated_at = utc_now()

        self.session.add(bill)
        self.session.commit()
        self.session.refresh(bill)
        return bill

    def delete(self, bill: BillRecord) -> None:
        self.session.delete(bill)
        self.session.commit()
