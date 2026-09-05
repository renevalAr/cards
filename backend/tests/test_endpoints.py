"""Tests for untested endpoints: PATCH /me, DELETE /me, PUT /cards/reorder"""
import uuid

def test_update_me_display_name(auth_client):
    """PATCH /api/auth/me updates display_name"""
    res = auth_client.patch("/api/auth/me", json={"display_name": "New Name"})
    assert res.status_code == 200
    data = res.json()
    assert data["display_name"] == "New Name"

def test_delete_me(auth_client):
    """DELETE /api/auth/me removes the user"""
    # Create a deck first so we can verify cascade
    deck_res = auth_client.post("/api/decks", json={"name": "To Delete"})
    assert deck_res.status_code == 201
    
    res = auth_client.delete("/api/auth/me")
    assert res.status_code == 200
    
    # Verify user is gone - login should fail
    login_res = auth_client.post("/api/auth/login", json={"email": "test@example.com", "password": "Test1234!"})
    assert login_res.status_code == 401

def test_reorder_cards(auth_client):
    """PUT /api/cards/reorder reorders cards in a deck"""
    # Create deck
    deck_res = auth_client.post("/api/decks", json={"name": "Reorder Deck"})
    deck_id = deck_res.json()["id"]
    
    # Create 3 cards
    card_ids = []
    for i in range(3):
        res = auth_client.post(f"/api/decks/{deck_id}/cards", json={
            "question": f"Q{i}", "answer": f"A{i}"
        })
        card_ids.append(res.json()["id"])
    
    # Reverse order
    reversed_ids = list(reversed(card_ids))
    res = auth_client.put("/api/cards/reorder", json={"card_ids": reversed_ids})
    assert res.status_code == 200
    
    # Verify new order
    res = auth_client.get(f"/api/decks/{deck_id}/cards")
    cards = res.json()["items"]
    returned_ids = [c["id"] for c in cards]
    assert returned_ids == reversed_ids

def test_reorder_cards_wrong_deck(auth_client):
    """PUT /api/cards/reorder rejects cards from different decks"""
    # Create two decks
    d1 = auth_client.post("/api/decks", json={"name": "Deck1"}).json()
    d2 = auth_client.post("/api/decks", json={"name": "Deck2"}).json()
    
    # Create cards in each
    c1 = auth_client.post(f"/api/decks/{d1['id']}/cards", json={"question": "Q1", "answer": "A1"}).json()
    c2 = auth_client.post(f"/api/decks/{d2['id']}/cards", json={"question": "Q2", "answer": "A2"}).json()
    
    # Try to reorder cards from different decks
    res = auth_client.put("/api/cards/reorder", json={"card_ids": [c1["id"], c2["id"]]})
    assert res.status_code in (400, 404, 422)
