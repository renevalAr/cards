import secrets


def generate_share_slug() -> str:
    return secrets.token_urlsafe(12)
