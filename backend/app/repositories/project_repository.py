from uuid import UUID

from sqlalchemy import case, select
from sqlalchemy.orm import Session

from app.core.time import utc_now
from app.models.project import ProjectCreate, ProjectRecord, ProjectUpdate


class ProjectRepository:
    def __init__(self, session: Session) -> None:
        self.session = session

    def create(self, payload: ProjectCreate) -> ProjectRecord:
        project = ProjectRecord(
            name=payload.name,
            description=payload.description,
            status=payload.status,
            area=payload.area,
        )
        project.tags = payload.tags
        self.session.add(project)
        self.session.commit()
        self.session.refresh(project)
        return project

    def list(
        self,
        *,
        include_archived: bool = False,
        status: str | None = None,
        tag: str | None = None,
        area: str | None = None,
    ) -> list[ProjectRecord]:
        status_order = case(
            (ProjectRecord.status == "active", 0),
            (ProjectRecord.status == "paused", 1),
            (ProjectRecord.status == "completed", 2),
            (ProjectRecord.status == "archived", 3),
            else_=4,
        )

        statement = select(ProjectRecord)
        if not include_archived:
            statement = statement.where(ProjectRecord.status != "archived")
        if status is not None:
            statement = statement.where(ProjectRecord.status == status)
        if area is not None:
            statement = statement.where(ProjectRecord.area == area)
        statement = statement.order_by(status_order, ProjectRecord.created_at.desc())

        projects = list(self.session.scalars(statement).all())
        if tag is None:
            return projects

        normalized_tag = tag.strip()
        if not normalized_tag:
            return projects
        return [project for project in projects if normalized_tag in project.tags]

    def get(self, project_id: UUID) -> ProjectRecord | None:
        return self.session.get(ProjectRecord, str(project_id))

    def update(self, project: ProjectRecord, payload: ProjectUpdate) -> ProjectRecord:
        updates = payload.model_dump(exclude_unset=True)
        tags = updates.pop("tags", None)

        for field, value in updates.items():
            setattr(project, field, value)
        if tags is not None:
            project.tags = tags
        project.updated_at = utc_now()

        self.session.add(project)
        self.session.commit()
        self.session.refresh(project)
        return project

    def delete(self, project: ProjectRecord) -> None:
        self.session.delete(project)
        self.session.commit()
