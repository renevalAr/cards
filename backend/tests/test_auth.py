import pytest


def test_register_success(client):
    res = client.post("/api/auth/register", json={
        "email": "new@example.com",
        "password": "SecurePass123!",
    })
    assert res.status_code == 201
    data = res.json()
    assert data["email"] == "new@example.com"
    assert "id" in data


def test_register_duplicate_email(client):
    user_data = {"email": "dup@example.com", "password": "SecurePass123!"}
    client.post("/api/auth/register", json=user_data)
    res = client.post("/api/auth/register", json=user_data)
    assert res.status_code == 409


def test_register_invalid_email(client):
    res = client.post("/api/auth/register", json={
        "email": "not-an-email",
        "password": "SecurePass123!",
    })
    assert res.status_code == 422


def test_register_short_password(client):
    res = client.post("/api/auth/register", json={
        "email": "short@example.com",
        "password": "123",
    })
    assert res.status_code == 422


def test_login_success(client):
    user_data = {"email": "login@example.com", "password": "SecurePass123!"}
    client.post("/api/auth/register", json=user_data)
    res = client.post("/api/auth/login", json=user_data)
    assert res.status_code == 200
    assert "access_token" in res.json()


def test_login_wrong_password(client):
    user_data = {"email": "wrongpw@example.com", "password": "SecurePass123!"}
    client.post("/api/auth/register", json=user_data)
    res = client.post("/api/auth/login", json={
        "email": user_data["email"],
        "password": "WrongPass123!",
    })
    assert res.status_code == 401


def test_get_me(auth_client):
    res = auth_client.get("/api/auth/me")
    assert res.status_code == 200
    assert res.json()["email"] == "test@example.com"


def test_get_me_unauthorized(client):
    res = client.get("/api/auth/me")
    assert res.status_code == 401
