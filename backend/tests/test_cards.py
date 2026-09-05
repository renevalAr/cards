

def test_create_card(auth_client):
    deck_id = auth_client.post("/api/decks", json={"name": "Test Deck"}).json()["id"]
    res = auth_client.post(f"/api/decks/{deck_id}/cards", json={
        "question": "What is Python?",
        "answer": "A programming language",
    })
    assert res.status_code == 201
    assert res.json()["question"] == "What is Python?"


def test_list_cards_pagination(auth_client):
    deck_id = auth_client.post("/api/decks", json={"name": "Paginated Deck"}).json()["id"]
    for i in range(5):
        auth_client.post(f"/api/decks/{deck_id}/cards", json={
            "question": f"Question {i}",
            "answer": f"Answer {i}",
        })
    res = auth_client.get(f"/api/decks/{deck_id}/cards?limit=3")
    assert res.status_code == 200
    data = res.json()
    assert len(data["items"]) == 3
    assert data["next_cursor"] is not None


def test_search_cards(auth_client):
    deck_id = auth_client.post("/api/decks", json={"name": "Search Deck"}).json()["id"]
    auth_client.post(f"/api/decks/{deck_id}/cards", json={
        "question": "What is FastAPI?",
        "answer": "A web framework",
    })
    auth_client.post(f"/api/decks/{deck_id}/cards", json={
        "question": "What is Django?",
        "answer": "Another web framework",
    })
    res = auth_client.get(f"/api/decks/{deck_id}/cards?search=FastAPI")
    assert res.status_code == 200
    assert len(res.json()["items"]) == 1


def test_update_card(auth_client):
    deck_id = auth_client.post("/api/decks", json={"name": "Update Deck"}).json()["id"]
    create_res = auth_client.post(f"/api/decks/{deck_id}/cards", json={
        "question": "Old question",
        "answer": "Old answer",
    })
    card_id = create_res.json()["id"]
    res = auth_client.patch(f"/api/cards/{card_id}", json={"question": "New question"})
    assert res.status_code == 200
    assert res.json()["question"] == "New question"


def test_delete_card(auth_client):
    deck_id = auth_client.post("/api/decks", json={"name": "Delete Deck"}).json()["id"]
    create_res = auth_client.post(f"/api/decks/{deck_id}/cards", json={
        "question": "To delete",
        "answer": "Answer",
    })
    card_id = create_res.json()["id"]
    res = auth_client.delete(f"/api/cards/{card_id}")
    assert res.status_code == 204
    res = auth_client.get(f"/api/decks/{deck_id}/cards")
    assert len(res.json()["items"]) == 0
