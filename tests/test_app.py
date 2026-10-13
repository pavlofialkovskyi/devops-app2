from app import app
#9 add dependencies for adding and managing the jwt token authentication
from datetime import datetime, timedelta, timezone
import jwt
from unittest.mock import patch
import os  # 


#9 define a jwt token to be given to user_id=1 for 5 min, returns Authorization Bearer
# we will use this function to run the tests related to the JWT token, both True and False because of expired token
def auth_header(user_id=1, minutes=5):
    payload = {
               "sub": str(user_id),
               "exp": datetime.now(timezone.utc) + timedelta(minutes=minutes)
               }
    token = jwt.encode(payload, os.environ["JWT_SECRET"], algorithm="HS256") 
# os.environ["JWT_SECRET"] instead of just "some random short strg", 
# because PyTest always loads conftest.py first automatically, then conftest writes the value onto the notice board
# then pytest loads test_app.py which imports app.py
    return {"Authorization": f"Bearer {token}"}



def test_health():
    client = app.test_client()
    response = client.get("/health")
    assert response.status_code == 200  # assert checks a true/false statement and reacts, CI/CD build fails if false
    assert response.get_json() == {"status": "ok"}


def test_create_message_missing_content():
    client = app.test_client()
    response = client.post("/messages", json={}, headers=auth_header()) 
#9  headers=auth_header() creates a real, signed token with the test secret, which bypasses token check for a simple message missing test
    assert response.status_code == 400


def test_get_messages_db_failure():
    client = app.test_client()
    with patch("app.get_db_connection", side_effect=Exception("DB unreachable")):
        response = client.get("/messages", headers=auth_header()) 
#9 again, to bypass the JWT token check for a postgres DB connection
        assert response.status_code == 500


#9 ------------------------------ Auth tests -----------------------------

#9 check the GET /messages response without authentication JWT, should return 401 error code
def test_messages_without_token():
    client = app.test_client()
    response = client.get("/messages") 
    assert response.status_code == 401

#9 check the GET /messages with an FALSE token and return 401 error code
def test_messages_with_fake_token():
    client = app.test_client()
    headers =  {"Authorization": "Bearer-has-a-false-token"} #9 a random false token
    response = client.get("/messages", headers=headers) #9 use this false token here
    assert response.status_code == 401

#9 check the GET /messages with an FALSE token and return 401 error code
def test_messages_with_fake_token():
    client = app.test_client()
    fake_headers = {"Authorization": "Bearer-has-a-false-token"} #9 a random false token
    response = client.get("/messages", headers=fake_headers) #9 use this false token here
    assert response.status_code == 401

#9 Also we want to ensure that the password during singup is 8 chars or longer
def test_singup_short_password():
    client = app.test_client()
    response = client.post("/signup", json={"email": "a@b.com", "password": "123"})
    assert response.status_code == 400