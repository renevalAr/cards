import pytest
from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

from app.main import app
from app.database import get_db, Base

TEST_DATABASE_URL = "postgresql://flashcards:flashcards@db:5432/flashcards"

engine = create_engine(TEST_DATABASE_URL)
Session = sessionmaker(bind=engine)


def override_get_db():
    db = Session()
    try:
        yield db
    finally:
        db.close()


@pytest.fixture(scope="session", autouse=True)
def setup_db():
    Base.metadata.drop_all(bind=engine)
    Base.metadata.create_all(bind=engine)
    yield
    Base.metadata.drop_all(bind=engine)


@pytest.fixture(autouse=True)
def clean_tables():
    yield
    with engine.connect() as conn:
        for table in reversed(Base.metadata.sorted_tables):
            conn.execute(table.delete())
        conn.commit()


@pytest.fixture
def client():
    app.dependency_overrides[get_db] = override_get_db
    with TestClient(app) as c:
        yield c


@pytest.fixture
def auth_client(client):
    """Client with authenticated user."""
    client.post("/api/auth/register", json={
        "email": "test@example.com",
        "password": "SecurePass123!",
    })
    client.post("/api/auth/login", json={
        "email": "test@example.com",
        "password": "SecurePass123!",
    })
    return client
