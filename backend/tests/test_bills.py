from uuid import uuid4


def test_create_bill(client) -> None:
    response = client.post("/bills", json={"name": "Rent", "due_date": "2026-07-01"})

    assert response.status_code == 201
    data = response.json()
    assert data["name"] == "Rent"
    assert data["due_date"] == "2026-07-01"
    assert data["currency"] == "INR"
    assert data["is_paid"] is False
    assert data["reminder_days_before"] == 3
    assert data["id"]
    assert data["created_at"]
    assert data["updated_at"]


def test_create_bill_requires_name_and_due_date(client) -> None:
    missing_name = client.post("/bills", json={"due_date": "2026-07-01"})
    missing_due_date = client.post("/bills", json={"name": "Internet"})

    assert missing_name.status_code == 422
    assert missing_due_date.status_code == 422


def test_create_bill_rejects_empty_name(client) -> None:
    response = client.post("/bills", json={"name": "   ", "due_date": "2026-07-01"})

    assert response.status_code == 422


def test_create_bill_uses_default_currency_inr(client) -> None:
    response = client.post("/bills", json={"name": "Phone", "due_date": "2026-07-10"})

    assert response.status_code == 201
    assert response.json()["currency"] == "INR"


def test_list_bills(client) -> None:
    client.post("/bills", json={"name": "Electricity", "due_date": "2026-07-15"})
    client.post("/bills", json={"name": "Water", "due_date": "2026-07-10"})

    response = client.get("/bills")

    assert response.status_code == 200
    assert [bill["name"] for bill in response.json()] == ["Water", "Electricity"]


def test_list_bills_orders_unpaid_first_then_due_date(client) -> None:
    client.post("/bills", json={"name": "Paid early", "due_date": "2026-07-01", "is_paid": True})
    client.post("/bills", json={"name": "Unpaid later", "due_date": "2026-07-20"})
    client.post("/bills", json={"name": "Unpaid earlier", "due_date": "2026-07-05"})

    response = client.get("/bills")

    assert response.status_code == 200
    assert [bill["name"] for bill in response.json()] == [
        "Unpaid earlier",
        "Unpaid later",
        "Paid early",
    ]


def test_get_bill_by_id(client) -> None:
    created = client.post("/bills", json={"name": "Insurance", "due_date": "2026-08-01"}).json()

    response = client.get(f"/bills/{created['id']}")

    assert response.status_code == 200
    assert response.json()["id"] == created["id"]
    assert response.json()["name"] == "Insurance"


def test_patch_bill_paid_status(client) -> None:
    created = client.post("/bills", json={"name": "Credit card", "due_date": "2026-07-12"}).json()

    response = client.patch(f"/bills/{created['id']}", json={"is_paid": True})

    assert response.status_code == 200
    data = response.json()
    assert data["is_paid"] is True
    assert data["updated_at"] >= created["updated_at"]


def test_patch_bill_amount_and_notes(client) -> None:
    created = client.post("/bills", json={"name": "Internet", "due_date": "2026-07-22"}).json()

    response = client.patch(
        f"/bills/{created['id']}",
        json={"amount": 1499.5, "notes": "Autopay enabled"},
    )

    assert response.status_code == 200
    data = response.json()
    assert data["amount"] == 1499.5
    assert data["notes"] == "Autopay enabled"


def test_delete_bill(client) -> None:
    created = client.post("/bills", json={"name": "Delete me", "due_date": "2026-07-30"}).json()

    delete_response = client.delete(f"/bills/{created['id']}")
    get_response = client.get(f"/bills/{created['id']}")

    assert delete_response.status_code == 204
    assert get_response.status_code == 404


def test_unknown_bill_returns_404(client) -> None:
    missing_id = uuid4()

    assert client.get(f"/bills/{missing_id}").status_code == 404
    assert client.patch(f"/bills/{missing_id}", json={"is_paid": True}).status_code == 404
    assert client.delete(f"/bills/{missing_id}").status_code == 404
