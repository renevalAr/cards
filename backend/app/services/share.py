import uuid


def generate_share_slug() -> str:
    return str(uuid.uuid4())[:8]
