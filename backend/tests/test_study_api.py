
import uuid


def test_start_session(auth_client):
    deck_res = auth_client.post("/api/decks", json={"name": "Study Deck"})
    deck_id = deck_res.json()["id"]
    res = auth_client.post(f"/api/study/session?deck_id={deck_id}")
    assert res.status_code == 201
    assert "id" in res.json()


def test_update_session(auth_client):
    deck_res = auth_client.post("/api/decks", json={"name": "Study Deck"})
    deck_id = deck_res.json()["id"]
    session_res = auth_client.post(f"/api/study/session?deck_id={deck_id}")
    session_id = session_res.json()["id"]
    res = auth_client.patch(f"/api/study/session/{session_id}?known=5&unknown=3")
    assert res.status_code == 200
    assert res.json()["known"] == 5
    assert res.json()["unknown"] == 3


def test_update_session_negative_rejected(auth_client):
    deck_res = auth_client.post("/api/decks", json={"name": "Study Deck"})
    deck_id = deck_res.json()["id"]
    session_res = auth_client.post(f"/api/study/session?deck_id={deck_id}")
    session_id = session_res.json()["id"]
    res = auth_client.patch(f"/api/study/session/{session_id}?known=-1")
    assert res.status_code == 400


def test_get_stats(auth_client):
    res = auth_client.get("/api/study/stats")
    assert res.status_code == 200
    data = res.json()
    assert "today" in data
    assert "total" in data
    assert "streak" in data


def test_session_not_found(auth_client):
    fake_id = str(uuid.uuid4())
    res = auth_client.patch(f"/api/study/session/{fake_id}?known=1")
    assert res.status_code == 404


def test_session_isolation(client):
    client.post("/api/auth/register", json={"email": "s1@example.com", "password": "Pass12345!"})
    client.post("/api/auth/login", json={"email": "s1@example.com", "password": "Pass12345!"})
    deck_res = client.post("/api/decks", json={"name": "D"})
    deck_id = deck_res.json()["id"]
    session_res = client.post(f"/api/study/session?deck_id={deck_id}")
    session_id = session_res.json()["id"]

    client.post("/api/auth/register", json={"email": "s2@example.com", "password": "Pass12345!"})
    client.post("/api/auth/login", json={"email": "s2@example.com", "password": "Pass12345!"})
    res = client.patch(f"/api/study/session/{session_id}?known=1")
    assert res.status_code == 404
