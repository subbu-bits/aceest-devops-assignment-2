"""Shared pytest fixtures."""
import pytest

from app import LATEST_VERSION, create_app


@pytest.fixture
def app(tmp_path):
    """A fresh app with its own temporary database for every test.

    The full suite always tests the latest feature set, so it passes in
    every image (1.0 ... 3.2.4). Version-specific behaviour is checked in
    test_versions.py.
    """
    test_app = create_app(db_path=str(tmp_path / "test.db"),
                          version=LATEST_VERSION)
    test_app.config["TESTING"] = True
    return test_app


@pytest.fixture
def client(app):
    """Flask test client: lets us call endpoints without a real server."""
    return app.test_client()


@pytest.fixture
def sample_client(client):
    """Creates one client called 'Arjun' that tests can use."""
    client.post("/clients", json={
        "name": "Arjun", "age": 28, "height": 175,
        "weight": 70, "program": "MG",
    })
    return "Arjun"
