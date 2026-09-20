# devops-app2

A Flask + PostgreSQL REST API, containerized with Docker, with schema managed via Alembic migrations and deployed to AWS behind a CloudFront distribution → Application Load Balancer → Auto Scaling Group, backed by RDS.

Rebuilt from scratch as a portfolio project to demonstrate hands-on DevOps fundamentals: containerization, container networking, environment/secrets management, database migrations, load balancing, CDN/edge security, CI/CD with keyless cloud authentication, and cloud deployment with autoscaling.

## Stack

- Python 3.12 / Flask
- PostgreSQL (16 locally via Docker, 17 on AWS RDS)
- Docker + Docker Compose
- Alembic (database schema migrations)
- GitHub Actions (CI/CD: test → build & publish to GHCR → trigger cloud deploy)
- AWS: EC2 Auto Scaling Group, Launch Template, Application Load Balancer, CloudFront (+ AWS WAF), RDS, Systems Manager (Parameter Store + Session Manager), IAM (including OIDC federation for GitHub Actions)

## API

| Method | Endpoint | Description |
|---|---|---|
| GET | /messages | List all messages |
| POST | /messages | Create a message (`{"content": "...", "image_url": "..."}`) |
| PUT | /messages/<id> | Update a message's content and/or image_url |
| DELETE | /messages/<id> | Delete a message |
| GET | /health | Health check |

## Running locally

1. Copy `.env` (see below) into the project root — never commit this file.
2. Run:

   docker compose up --build

3. Apply database migrations (schema is managed by Alembic, not by Docker Compose):

   alembic upgrade head

4. App available at `http://localhost:5000`.

## Environment variables (`.env`, not committed)

DB_HOST=localhost
DB_PORT=5432
DB_NAME=devops_app2_db
DB_USER=app_user
DB_PASSWORD=changeme_local_dev_password

## Database migrations

Schema changes are managed with Alembic, not manual SQL scripts, so the same migration history applies identically to the local database and to the AWS RDS instance.

- Create a new migration: `alembic revision -m "description"`
- Apply pending migrations: `alembic upgrade head`
- Roll back the last migration: `alembic downgrade -1`

Migration files live in `alembic/versions/`. `alembic/env.py` loads `.env` via `python-dotenv` and builds the database URL from the same `DB_*` variables used by the app.

## Cloud architecture (AWS)

Traffic flow: **CloudFront (HTTPS, edge caching, AWS WAF)** → **Application Load Balancer (HTTP)** → **Target Group** → **EC2 Auto Scaling Group** → **RDS (PostgreSQL)**.

Infrastructure is currently provisioned manually through the AWS Console (Terraform is a planned future phase).

**Components:**

- **Launch Template** — defines the EC2 instance config and a bootstrap script (`scripts/bootstrap.sh`) run as User Data on every instance launch.
- **Auto Scaling Group** — maintains desired EC2 capacity across multiple Availability Zones, registered with the target group so the ALB always routes only to healthy instances.
- **Application Load Balancer** — public HTTP(S) entry point; forwards to a target group performing health checks against `/health`.
- **CloudFront** — CDN in front of the ALB; terminates HTTPS for end users, forwards to the ALB over HTTP internally. Cache policy set to `CachingDisabled` since API responses are dynamic. Includes **AWS WAF** with SQL-injection protection, rate-based limiting, and application-layer DDoS protection (currently in monitor mode).
- **RDS (PostgreSQL)** — persistent database, not publicly accessible, reachable only from EC2 instances via security group rules.
- **IAM Role (EC2)** — grants EC2 instances SSM access (Session Manager, no SSH) and scoped `ssm:GetParameter` permissions for specific secrets.
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

GitHub Actions runs on every push to `main`:

1. **Test** — installs dependencies, runs the test suite.
2. **Build & push** — builds the Docker image and publishes it to GitHub Container Registry (GHCR), tagged `:latest`.
3. **Deploy** — authenticates to AWS via OIDC (no stored credentials), then triggers an Auto Scaling Group **Instance Refresh**, which rolls out the new image to running EC2 instances with controlled minimum-healthy-percentage, and each instance's boot flow applies any pending Alembic migrations automatically.

The deploy step only runs if the test and build steps both succeed.

## Roadmap

- [x] Containerized app + Docker Compose local dev
- [x] CI/CD pipeline to GHCR
- [x] EC2 Auto Scaling Group + RDS + Alembic-managed schema
- [x] Application Load Balancer
- [x] CloudFront CDN + AWS WAF
- [x] Automated CI/CD deploy via GitHub OIDC + ASG Instance Refresh
- [ ] S3-backed image uploads
- [ ] Read-only landing page (Jinja2)
- [ ] Terraform (Infrastructure as Code)
- [ ] Kubernetes (EKS), Ansible