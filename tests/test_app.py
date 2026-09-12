from app import app

def test_health():
    client = app.test_client()
    response = client.get("/health")
    assert response.status_code == 200
    assert response.get_json() == {"status": "ok"}

def test_create_message_missing_content():
    client = app.test_client()
    response = client.post("/messages", json={})
    assert response.status_code == 400

from unittest.mock import patch

def test_get_messages_db_failure():
    client = app.test_client()
    with patch("app.get_db_connection", side_effect=Exception("DB unreachable")):
        response = client.get("/messages")
        assert response.status_code == 500