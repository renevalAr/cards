import pytest


def test_verify_request_requires_auth(client):
    """verify-request without auth should return 401"""
    res = client.post("/api/auth/verify-request")
    assert res.status_code == 401


def test_verify_request_when_not_configured(client, auth_client):
    """verify-request when SMTP is not configured should return 503"""
    res = auth_client.post("/api/auth/verify-request")
    # SMTP not configured in test env, should return 503
    assert res.status_code == 503


def test_verify_with_invalid_token(client):
    """verify with bad token should return 400"""
    res = client.post("/api/auth/verify?token=invalid-token-123")
    assert res.status_code == 400


def test_verify_with_empty_token(client):
    """verify with empty token should return 400 or 422"""
    res = client.post("/api/auth/verify?token=")
    assert res.status_code in (400, 422)


def test_user_starts_unverified(client, auth_client):
    """New user should have is_verified=False"""
    res = auth_client.get("/api/auth/me")
    assert res.status_code == 200
    assert res.json()["is_verified"] is False


def test_verify_request_idempotent(client, auth_client):
    """Calling verify-request twice should not crash"""
    res1 = auth_client.post("/api/auth/verify-request")
    res2 = auth_client.post("/api/auth/verify-request")
    # Both should return 503 (SMTP not configured) or 200
    assert res1.status_code in (200, 503)
    assert res2.status_code in (200, 503)
