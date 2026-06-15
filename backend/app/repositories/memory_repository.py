from app.models.domain import Bill, MemoryItem, MoodLog, Project, Todo


class InMemoryRepository:
    def __init__(self) -> None:
        self._memory_items: list[MemoryItem] = []
        self._todos: list[Todo] = []
        self._bills: list[Bill] = []
        self._projects: list[Project] = []
        self._mood_logs: list[MoodLog] = []

    def list_memory_items(self) -> list[MemoryItem]:
        return list(self._memory_items)

    def add_memory_item(self, item: MemoryItem) -> MemoryItem:
        self._memory_items.append(item)
        return item

    def list_todos(self) -> list[Todo]:
        return list(self._todos)

    def add_todo(self, todo: Todo) -> Todo:
        self._todos.append(todo)
        return todo

    def list_bills(self) -> list[Bill]:
        return list(self._bills)

    def add_bill(self, bill: Bill) -> Bill:
        self._bills.append(bill)
        return bill

    def list_projects(self) -> list[Project]:
        return list(self._projects)

    def add_project(self, project: Project) -> Project:
        self._projects.append(project)
        return project

    def list_mood_logs(self) -> list[MoodLog]:
        return list(self._mood_logs)

    def add_mood_log(self, mood_log: MoodLog) -> MoodLog:
        self._mood_logs.append(mood_log)
        return mood_log


repository = InMemoryRepository()

