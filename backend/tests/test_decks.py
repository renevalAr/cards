

def test_create_deck(auth_client):
    res = auth_client.post("/api/decks", json={
        "name": "Test Deck",
        "description": "A test deck",
    })
    assert res.status_code == 201
    data = res.json()
    assert data["name"] == "Test Deck"
    assert data["cards_count"] == 0


def test_list_decks(auth_client):
    auth_client.post("/api/decks", json={"name": "Deck 1"})
    auth_client.post("/api/decks", json={"name": "Deck 2"})
    res = auth_client.get("/api/decks")
    assert res.status_code == 200
    assert len(res.json()) >= 2


def test_get_deck(auth_client):
    create_res = auth_client.post("/api/decks", json={"name": "My Deck"})
    deck_id = create_res.json()["id"]
    res = auth_client.get(f"/api/decks/{deck_id}")
    assert res.status_code == 200
    assert res.json()["name"] == "My Deck"


def test_update_deck(auth_client):
    create_res = auth_client.post("/api/decks", json={"name": "Old Name"})
    deck_id = create_res.json()["id"]
    res = auth_client.patch(f"/api/decks/{deck_id}", json={"name": "New Name"})
    assert res.status_code == 200
    assert res.json()["name"] == "New Name"


def test_delete_deck(auth_client):
    create_res = auth_client.post("/api/decks", json={"name": "To Delete"})
    deck_id = create_res.json()["id"]
    res = auth_client.delete(f"/api/decks/{deck_id}")
    assert res.status_code == 204
    res = auth_client.get(f"/api/decks/{deck_id}")
    assert res.status_code == 404


def test_deck_isolation(client):
    client.post("/api/auth/register", json={"email": "user1@example.com", "password": "Pass12345!"})
    client.post("/api/auth/login", json={"email": "user1@example.com", "password": "Pass12345!"})
    client.post("/api/decks", json={"name": "Private Deck"})
    res = client.get("/api/decks")
    assert res.status_code == 200
    assert len(res.json()) == 1
