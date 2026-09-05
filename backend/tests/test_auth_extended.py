
def test_logout_revokes_refresh_token(client):
    client.post("/api/auth/register", json={"email": "rev@test.com", "password": "Pass12345!"})
    login_res = client.post("/api/auth/login", json={"email": "rev@test.com", "password": "Pass12345!"})
    assert login_res.status_code == 200

    logout_res = client.post("/api/auth/logout")
    assert logout_res.status_code == 200

    refresh_token = None
    for cookie in client.cookies.jar:
        if cookie.name == "refresh_token":
            refresh_token = cookie.value
            break

    if refresh_token:
        refresh_res = client.post("/api/auth/refresh")
        assert refresh_res.status_code == 401


def test_refresh_without_token(client):
    res = client.post("/api/auth/refresh")
    assert res.status_code == 401


def test_me_without_auth(client):
    res = client.get("/api/auth/me")
    assert res.status_code == 401


def test_register_duplicate_email(client):
    client.post("/api/auth/register", json={"email": "dup@test.com", "password": "Pass12345!"})
    res = client.post("/api/auth/register", json={"email": "dup@test.com", "password": "Pass12345!"})
    assert res.status_code == 409


def test_login_wrong_password(client):
    client.post("/api/auth/register", json={"email": "wp@test.com", "password": "Pass12345!"})
    res = client.post("/api/auth/login", json={"email": "wp@test.com", "password": "WrongPass1!"})
    assert res.status_code == 401


def test_register_weak_password(client):
    res = client.post("/api/auth/register", json={"email": "weak@test.com", "password": "weak"})
    assert res.status_code == 422


def test_me_returns_user_info(auth_client):
    res = auth_client.get("/api/auth/me")
    assert res.status_code == 200
    data = res.json()
    assert data["email"] == "test@example.com"
    assert "id" in data
