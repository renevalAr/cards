
import uuid


def test_enable_sharing(auth_client):
    create_res = auth_client.post("/api/decks", json={"name": "Share Deck"})
    deck_id = create_res.json()["id"]
    res = auth_client.post(f"/api/decks/{deck_id}/share")
    assert res.status_code == 200
    assert "share_slug" in res.json()


def test_disable_sharing(auth_client):
    create_res = auth_client.post("/api/decks", json={"name": "Share Deck"})
    deck_id = create_res.json()["id"]
    auth_client.post(f"/api/decks/{deck_id}/share")
    res = auth_client.delete(f"/api/decks/{deck_id}/share")
    assert res.status_code == 204


def test_get_public_deck(auth_client):
    create_res = auth_client.post("/api/decks", json={"name": "Public Deck"})
    deck_id = create_res.json()["id"]
    share_res = auth_client.post(f"/api/decks/{deck_id}/share")
    slug = share_res.json()["share_slug"]
    res = auth_client.get(f"/api/decks/share/{slug}")
    assert res.status_code == 200
    assert res.json()["name"] == "Public Deck"


def test_get_public_cards(auth_client):
    create_res = auth_client.post("/api/decks", json={"name": "Public Deck"})
    deck_id = create_res.json()["id"]
    auth_client.post(f"/api/decks/{deck_id}/cards", json={"question": "Q1", "answer": "A1"})
    share_res = auth_client.post(f"/api/decks/{deck_id}/share")
    slug = share_res.json()["share_slug"]
    res = auth_client.get(f"/api/decks/share/{slug}/cards")
    assert res.status_code == 200
    assert len(res.json()) >= 1


def test_public_deck_not_found(client):
    res = client.get("/api/decks/share/nonexistent-slug")
    assert res.status_code == 404


def test_sharing_requires_auth(client):
    create_res = client.post("/api/auth/register", json={"email": "s@example.com", "password": "Pass12345!"})
    if create_res.status_code != 201:
        client.post("/api/auth/login", json={"email": "s@example.com", "password": "Pass12345!"})
    deck_res = client.post("/api/decks", json={"name": "D"})
    assert deck_res.status_code != 401, "Auth fixture failed — test cannot proceed"
    deck_id = deck_res.json()["id"]
    client.post("/api/auth/logout")
    res = client.post(f"/api/decks/{deck_id}/share")
    assert res.status_code in (401, 403)
