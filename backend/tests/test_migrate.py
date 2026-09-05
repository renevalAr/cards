

def test_migrate_data(auth_client):
    payload = {
        "version": "migration-v1",
        "decks": [
            {
                "name": "Migrated Deck",
                "cards": [
                    {"question": "Q1", "answer": "A1"},
                    {"question": "Q2", "answer": "A2"},
                ],
            }
        ],
    }
    res = auth_client.post("/api/migrate", json=payload)
    assert res.status_code == 201
    assert res.json()["total_decks"] == 1


def test_migrate_empty_decks(auth_client):
    res = auth_client.post("/api/migrate", json={"decks": []})
    assert res.status_code == 400


def test_migrate_unauthorized(client):
    res = client.post("/api/migrate", json={"decks": [{"name": "Test", "cards": []}]})
    assert res.status_code == 401


def test_migrate_multiple_decks(auth_client):
    payload = {
        "version": "migration-v1",
        "decks": [
            {"name": f"Deck {i}", "cards": [{"question": f"Q{i}", "answer": f"A{i}"}]}
            for i in range(3)
        ],
    }
    res = auth_client.post("/api/migrate", json=payload)
    assert res.status_code == 201
    assert res.json()["total_decks"] == 3
