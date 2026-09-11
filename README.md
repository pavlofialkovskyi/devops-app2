# devops-app2

A small Flask + PostgreSQL REST API, containerized with Docker and orchestrated locally via Docker Compose. Rebuilt from scratch as a portfolio project to demonstrate hands-on DevOps fundamentals: containerization, container networking, environment/secrets management, and full CRUD against a persistent database.

## Stack
- Python 3.12 / Flask
- PostgreSQL 16
- Docker + Docker Compose

## API
| Method | Endpoint | Description |
|---|---|---|
| GET | /messages | List all messages |
| POST | /messages | Create a message (`{"content": "..."}`) |
| PUT | /messages/<id> | Update a message's content |
| DELETE | /messages/<id> | Delete a message |

## Running locally

1. Copy `.env` (see below) into the project root — never commit this file.
2. Run:

docker compose up --build

3. App available at `http://localhost:5000`.

## Environment variables (`.env`, not committed)

DB_HOST=localhost
DB_PORT=5432
DB_NAME=devops_app2_db
DB_USER=app_user
DB_PASSWORD=changeme_local_dev_password