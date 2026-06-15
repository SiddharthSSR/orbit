from uuid import uuid4


def test_create_mood_check_in(client) -> None:
    response = client.post(
        "/moods",
        json={"mood": "focused", "energy": 4, "notes": "Deep work morning", "check_in_date": "2026-06-16"},
    )

    assert response.status_code == 201
    data = response.json()
    assert data["mood"] == "focused"
    assert data["energy"] == 4
    assert data["notes"] == "Deep work morning"
    assert data["check_in_date"] == "2026-06-16"
    assert data["id"]
    assert data["created_at"]
    assert data["updated_at"]


def test_create_mood_defaults_check_in_date(client) -> None:
    response = client.post("/moods", json={"mood": "calm", "energy": 3})

    assert response.status_code == 201
    data = response.json()
    assert data["check_in_date"] == data["created_at"][:10]


def test_list_moods(client) -> None:
    client.post("/moods", json={"mood": "calm", "energy": 3, "check_in_date": "2026-06-15"})
    client.post("/moods", json={"mood": "focused", "energy": 4, "check_in_date": "2026-06-16"})

    response = client.get("/moods")

    assert response.status_code == 200
    assert [mood["mood"] for mood in response.json()] == ["focused", "calm"]


def test_list_moods_orders_by_check_in_date_desc(client) -> None:
    client.post("/moods", json={"mood": "older", "energy": 2, "check_in_date": "2026-06-14"})
    client.post("/moods", json={"mood": "newer", "energy": 5, "check_in_date": "2026-06-16"})
    client.post("/moods", json={"mood": "middle", "energy": 3, "check_in_date": "2026-06-15"})

    response = client.get("/moods")

    assert response.status_code == 200
    assert [mood["mood"] for mood in response.json()] == ["newer", "middle", "older"]


def test_get_mood_by_id(client) -> None:
    created = client.post("/moods", json={"mood": "neutral", "energy": 3}).json()

    response = client.get(f"/moods/{created['id']}")

    assert response.status_code == 200
    assert response.json()["id"] == created["id"]
    assert response.json()["mood"] == "neutral"


def test_patch_mood_energy_and_notes(client) -> None:
    created = client.post("/moods", json={"mood": "tired", "energy": 2, "notes": "Low sleep"}).json()

    response = client.patch(
        f"/moods/{created['id']}",
        json={"mood": "focused", "energy": 4, "notes": "Recovered after lunch"},
    )

    assert response.status_code == 200
    data = response.json()
    assert data["mood"] == "focused"
    assert data["energy"] == 4
    assert data["notes"] == "Recovered after lunch"
    assert data["updated_at"] >= created["updated_at"]


def test_delete_mood(client) -> None:
    created = client.post("/moods", json={"mood": "excited", "energy": 5}).json()

    delete_response = client.delete(f"/moods/{created['id']}")
    get_response = client.get(f"/moods/{created['id']}")

    assert delete_response.status_code == 204
    assert get_response.status_code == 404


def test_unknown_mood_returns_404(client) -> None:
    missing_id = uuid4()

    assert client.get(f"/moods/{missing_id}").status_code == 404
    assert client.patch(f"/moods/{missing_id}", json={"energy": 3}).status_code == 404
    assert client.delete(f"/moods/{missing_id}").status_code == 404


def test_mood_validation_fails_for_blank_mood(client) -> None:
    response = client.post("/moods", json={"mood": "   ", "energy": 3})

    assert response.status_code == 422


def test_mood_validation_fails_for_energy_out_of_range(client) -> None:
    low = client.post("/moods", json={"mood": "calm", "energy": 0})
    high = client.post("/moods", json={"mood": "calm", "energy": 6})

    assert low.status_code == 422
    assert high.status_code == 422


def test_mood_date_filtering(client) -> None:
    client.post("/moods", json={"mood": "old", "energy": 2, "check_in_date": "2026-06-10"})
    client.post("/moods", json={"mood": "inside", "energy": 4, "check_in_date": "2026-06-15"})
    client.post("/moods", json={"mood": "future", "energy": 5, "check_in_date": "2026-06-20"})

    response = client.get("/moods", params={"from_date": "2026-06-12", "to_date": "2026-06-18"})

    assert response.status_code == 200
    assert [mood["mood"] for mood in response.json()] == ["inside"]


def test_mood_limit(client) -> None:
    client.post("/moods", json={"mood": "one", "energy": 1, "check_in_date": "2026-06-10"})
    client.post("/moods", json={"mood": "two", "energy": 2, "check_in_date": "2026-06-11"})
    client.post("/moods", json={"mood": "three", "energy": 3, "check_in_date": "2026-06-12"})

    response = client.get("/moods", params={"limit": 2})

    assert response.status_code == 200
    assert [mood["mood"] for mood in response.json()] == ["three", "two"]
