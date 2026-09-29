# devops-app2

A Flask + PostgreSQL REST API, containerized with Docker, with schema managed via Alembic migrations and deployed to AWS behind a CloudFront distribution → Application Load Balancer → Auto Scaling Group, backed by RDS.

Rebuilt from scratch as a portfolio project to demonstrate hands-on DevOps fundamentals: containerization, container networking, environment/secrets management, database migrations, load balancing, CDN/edge security, CI/CD with keyless cloud authentication, cloud deployment with autoscaling, and Infrastructure as Code.

## Stack

- Python 3.12 / Flask
- PostgreSQL (16 locally via Docker, 17 on AWS RDS)
- Docker + Docker Compose
- Alembic (database schema migrations)
- boto3 (AWS SDK for Python — S3 file storage)
- MinIO (local S3-compatible emulator for development)
- Terraform (Infrastructure as Code)
- GitHub Actions (CI/CD: test → build & publish to GHCR → trigger cloud deploy)
- AWS: EC2 Auto Scaling Group, Launch Template, Application Load Balancer, CloudFront (+ AWS WAF), RDS, S3, Systems Manager (Parameter Store + Session Manager), IAM (including OIDC federation for GitHub Actions)

## API

| Method | Endpoint | Description |
|---|---|---|
| GET | /messages | List messages (supports `?limit=&offset=` pagination) |
| POST | /uploads/presign | Get a short-lived presigned S3 upload URL and a generated `media_key` (`{"filename": "..."}`) |
| POST | /messages | Create a message — content or a file, never both (`{"content": "..."}` or `{"media_key": "...", "original_filename": "..."}`) |
| PUT | /messages/<id> | Update a message's content and/or attached file |
| DELETE | /messages/<id> | Delete a message; if it had a file attached, also deletes it from S3 |
| GET | /health | Health check |

## Running locally

1. Copy `.env` (see below) into the project root — never commit this file.
2. Run:

   docker compose up --build

   This starts Postgres, the app, and MinIO (a local S3-compatible emulator, so file uploads can be tested fully offline before touching real AWS).
3. Create a bucket in MinIO's web console (`http://localhost:9001`, credentials from `docker-compose.yml`) matching the name set in `S3_UPLOADS_BUCKET`.
4. Apply database migrations (schema is managed by Alembic, not by Docker Compose):

   alembic upgrade head

5. App available at `http://localhost:5000`.

## Environment variables (`.env`, not committed)

DB_HOST=localhost
DB_PORT=5432
DB_NAME=devops_app2_db
DB_USER=app_user
DB_PASSWORD=changeme_local_dev_password
S3_UPLOADS_BUCKET=devops-uploads-local
S3_ENDPOINT_URL=http://minio:9000
S3_PUBLIC_ENDPOINT_URL=http://localhost:9000

In production, `S3_ENDPOINT_URL`/`S3_PUBLIC_ENDPOINT_URL` are left unset entirely, so boto3 falls back to real AWS S3 automatically — the same code path handles both environments with no branching logic.

## File attachments (GDPR-aware design)

Messages can include an uploaded file (e.g. a CV or other personal document) instead of plain text — never both in the same message. Files are uploaded directly from the client to a private S3 bucket using short-lived (300-second) presigned URLs, so the app server itself never touches the raw file bytes. Each file is stored under a random UUID key (`media_key`), never its real filename, to avoid collisions and keep storage private; the original filename is kept separately in Postgres (`original_filename`) and used only to relabel the file on download.

Downloading works the same way in reverse: a fresh, short-lived presigned download URL is generated on every read, presenting the file under its real name via `Content-Disposition`. Deleting a message that has a file attached also deletes that file from S3, preventing orphaned storage; a 30-day S3 lifecycle rule provides a backup expiration in case a delete ever fails, and failures are logged rather than silently ignored.

## Database migrations

Schema changes are managed with Alembic, not manual SQL scripts, so the same migration history applies identically to the local database and to the AWS RDS instance.

- Create a new migration: `alembic revision -m "description"`
- Apply pending migrations: `alembic upgrade head`
- Roll back the last migration: `alembic downgrade -1`

Migration files live in `alembic/versions/`. `alembic/env.py` loads `.env` via `python-dotenv` and builds the database URL from the same `DB_*` variables used by the app.

## Cloud architecture (AWS)

Traffic flow: **CloudFront (HTTPS, edge caching, AWS WAF)** → **Application Load Balancer (HTTP)** → **Target Group** → **EC2 Auto Scaling Group** → **RDS (PostgreSQL)**.

Infrastructure is fully provisioned via Terraform, with remote state stored in S3 and locked via DynamoDB.

**Components:**

- **Launch Template** — defines the EC2 instance config and a bootstrap script (`scripts/bootstrap.sh`) run as User Data on every instance launch.
- **Auto Scaling Group** — maintains desired EC2 capacity across multiple Availability Zones, registered with the target group so the ALB always routes only to healthy instances.
- **Application Load Balancer** — public HTTP(S) entry point; forwards to a target group performing health checks against `/health`.
- **CloudFront** — CDN in front of the ALB; terminates HTTPS for end users, forwards to the ALB over HTTP internally. Cache policy set to `CachingDisabled` since API responses are dynamic. Includes **AWS WAF** with SQL-injection protection, rate-based limiting, and application-layer DDoS protection (currently in monitor mode).
- **RDS (PostgreSQL)** — persistent database, not publicly accessible, reachable only from EC2 instances via security group rules.
- **S3 (uploads bucket)** — private bucket for user-uploaded file attachments; blocks all public access, SSE-S3 encryption at rest, a 30-day lifecycle rule for GDPR-aligned retention, and an IAM policy scoped to only `PutObject`/`GetObject`/`DeleteObject` on this bucket, attached to the EC2 role.
- **IAM Role (EC2)** — grants EC2 instances SSM access (Session Manager, no SSH), scoped `ssm:GetParameter` permissions for specific secrets, and scoped S3 access to the uploads bucket.
- **IAM Role (GitHub Actions, OIDC)** — a separate role trusted via GitHub's OIDC identity provider, scoped to this exact repo and branch, with narrow permission to trigger an ASG instance refresh. No long-lived AWS credentials are stored in GitHub — each workflow run authenticates with a short-lived token issued at run time.
- **SSM Parameter Store** — stores the DB password and GHCR pull token as SecureString parameters, fetched at boot time.
- **Security Groups** — ALB SG (public 80/443) → EC2 SG (5000, source = ALB SG) → RDS SG (5432, source = EC2 SG).

**Boot flow (`scripts/bootstrap.sh`):**

1. Install Docker, AWS CLI, and the PostgreSQL client.
2. Create a Docker network (`devops-net`) so containers can resolve each other by name.
3. Fetch the DB password from SSM Parameter Store.
4. Ensure the target database exists on RDS (idempotent check).
5. Log in to GHCR using a token from SSM Parameter Store, then pull the latest app image.
6. Run a one-off, self-removing container (`docker run --rm ...`) that executes `alembic upgrade head` against RDS, applying any pending schema migrations.
7. Start the application container.

This means every new or refreshed EC2 instance always pulls the latest published image and brings the RDS schema up to date automatically — no manual SQL, ever, against the cloud database.

## CI/CD

GitHub Actions runs on every push to `main` and on every pull request targeting `main`:

1. **Test** — installs dependencies, runs the test suite. Runs on both pushes to `main` and on pull requests, and is a required status check before a PR can be merged.
2. **Build & push** — builds the Docker image and publishes it to GitHub Container Registry (GHCR), tagged `:latest`. Runs only on pushes to `main` (never on a pull request).
3. **Deploy** — authenticates to AWS via OIDC (no stored credentials), then triggers an Auto Scaling Group **Instance Refresh**, which rolls out the new image to running EC2 instances with controlled minimum-healthy-percentage, and each instance's boot flow applies any pending Alembic migrations automatically. Runs only on pushes to `main`.

The deploy step only runs if the test and build steps both succeed. Direct pushes to `main` are blocked by branch protection rules — all changes go through a pull request.

## Roadmap

- [x] Containerized app + Docker Compose local dev
- [x] CI/CD pipeline to GHCR
- [x] EC2 Auto Scaling Group + RDS + Alembic-managed schema
- [x] Application Load Balancer
- [x] CloudFront CDN + AWS WAF
- [x] Automated CI/CD deploy via GitHub OIDC + ASG Instance Refresh
- [x] S3-backed file attachments (GDPR-aware, presigned URLs)
- [x] Terraform (Infrastructure as Code)