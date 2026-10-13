# devops-app2

A Flask + PostgreSQL REST API, containerized with Docker, with schema managed via Alembic migrations and deployed to AWS behind a CloudFront distribution → Application Load Balancer → Auto Scaling Group, backed by RDS.

Rebuilt from scratch as a portfolio project to demonstrate hands-on DevOps fundamentals: containerization, container networking, environment/secrets management, database migrations, load balancing, CDN/edge security, CI/CD with keyless cloud authentication, cloud deployment with autoscaling, and Infrastructure as Code.

## Stack

- Python 3.12 / Flask
- PostgreSQL (16 locally via Docker, 16 on AWS RDS)
- Docker + Docker Compose
- Alembic (database schema migrations)
- boto3 (AWS SDK for Python — S3 file storage)
- MinIO (local S3-compatible emulator for development)
- Terraform (Infrastructure as Code)
- GitHub Actions (CI/CD: test → build & publish to GHCR → trigger cloud deploy)
- AWS: EC2 Auto Scaling Group, Launch Template, Application Load Balancer, CloudFront (+ AWS WAF earlier manual setup), RDS, S3, Systems Manager (Parameter Store + Session Manager), IAM (including OIDC federation for GitHub Actions)
- Cloudflare (DNS for ACM certificate validation).
- Argon2id (argon2-cffi) for password hashing. PyJWT for authentication tokens.



## API

Method >    Endpoint         >   Auth           >  Description 

POST   > 	/signup	        >	               >  Create an account ({"email", "password"}, min. 8 chars)
POST   >    /login	        >                  > 	Returns a JWT access token (1 hour)
GET    >  	/messages	     >   Bearer token	>  List messages (supports `?limit=&offset=` pagination)
POST   > 	/uploads/presign >   Bearer token	>  Get a short-lived presigned S3 upload URL and a generated `media_key` (`{"filename": "..."}`)
POST   > 	/messages    	  >   Bearer token	>  Create a message — content or a file, never both (`{"content": "..."}` or `{"media_key": "...", "original_filename": "..."}`)
PUT    > 	/messages/<id>	  >   Bearer token	>  Update a message's content and/or attached file 
DELETE > 	/messages/<id>	  >   Bearer token	>  Delete a message; if it had a file attached, also deletes it from S3
GET    >	   /health	        >                  >	Health check   
 

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
JWT_SECRET: ${JWT_SECRET}

In production, `S3_ENDPOINT_URL`/`S3_PUBLIC_ENDPOINT_URL` are left unset entirely, so boto3 falls back to real AWS S3 automatically — the same code path handles both environments with no branching logic.

docker-compose.yml passes JWT_SECRET and S3_PUBLIC_ENDPOINT_URL to the container.

## File attachments (GDPR-aware design)

Messages can include an uploaded file (e.g. a CV or other personal document) instead of plain text — never both in the same message. Files are uploaded directly from the client to a private S3 bucket using short-lived (300-second) presigned URLs, so the app server itself never touches the raw file bytes. Each file is stored under a random UUID key (`media_key`), never its real filename, to avoid collisions and keep storage private; the original filename is kept separately in Postgres (`original_filename`) and used only to relabel the file on download.

Downloading works the same way in reverse: a fresh, short-lived presigned download URL is generated on every read, presenting the file under its real name via `Content-Disposition`. Deleting a message that has a file attached also deletes that file from S3, preventing orphaned storage; a 30-day S3 lifecycle rule provides a backup expiration in case a delete ever fails, and failures are logged rather than silently ignored.

## Database migrations

Schema changes are managed with Alembic, not manual SQL scripts, so the same migration history applies identically to the local database and to the AWS RDS instance.

- Create a new migration: `alembic revision -m "description"`
- Apply pending migrations: `alembic upgrade head`
- Roll back the last migration: `alembic downgrade -1`

Migration files live in `alembic/versions/`. `alembic/env.py` loads `.env` via `python-dotenv` and builds the database URL from the same `DB_*` variables used by the app.

## Authentication, local app container

- Data Migration: users table (email, Argon2id password hash) linked to messages.user_id by a foreign key with ON DELETE CASCADE
- passwords never stored, only salted Argon2id hashes, and the same error for unknown email and wrong password
- JWT signed with HS256, sub = user id, expires after 1 hour
- every protected route checks the token, and SQL filters by user_id, so users only see and change their own data
- SQL queries are parameterized (%s), and a test verifies injection input stays out of the SQL
- status: working locally


## Cloud architecture (AWS)

Traffic flow: **CloudFront + WAF** → **Application Load Balancer** → **Target Group** → **EC2 Auto Scaling Group** → **RDS (PostgreSQL)**.

Everything is provisioned with Terraform. Remote state is stored in S3 and locked with DynamoDB.

**Components:**

- **VPC** – two Availability Zones. Public subnets for the ALB and NAT Gateway, private subnets for EC2 and RDS. The NAT Gateway gives the private instances outbound internet access (e.g. pulling from GHCR).
- **Launch Template** – Amazon Linux 2023, t3.micro, IAM instance profile, and `scripts/bootstrap.sh` as User Data. IMDSv2 is required, with hop limit 2 so the container can use the instance role.
- **Auto Scaling Group** – 1 to 3 instances in the private subnets, registered with the target group and using ELB health checks.
- **Application Load Balancer** – HTTPS listener with an ACM certificate, forwarding to the target group (health check on `/health`). HTTP redirects to HTTPS.
- **ACM certificate** – covers `fatcontract.com` and `origin.fatcontract.com`, validated through DNS records in Cloudflare. `origin.fatcontract.com` points to the ALB so CloudFront can connect to it over HTTPS.
- **CloudFront** – sits in front of the ALB and connects to it over HTTPS. Caching is off because API responses are dynamic. The `Authorization` header is forwarded so JWTs reach the app.
- **AWS WAF** – attached to CloudFront. Uses the AWS Common and SQL-injection rule sets, plus a rate limit of 300 requests per 5 minutes per IP.
- **RDS (PostgreSQL 16)** – Multi-AZ, in private subnets, not publicly accessible. User, database and a random password are created by Terraform. Schema is managed with Alembic.
- **S3 (uploads bucket)** – private bucket for user file attachments. Public access blocked, SSE-S3 encryption, 30-day lifecycle rule, and CORS for browser uploads through presigned URLs. The EC2 role can only put, get and delete objects here.
- **IAM Role (EC2)** – Session Manager access (no SSH), read access to specific SSM parameters, and access to the uploads bucket.
- **IAM Role (GitHub Actions, OIDC)** – trusted only for this repo and branch, allowed to start an ASG instance refresh. No AWS keys are stored in GitHub.
- **SSM Parameter Store** – `db_password` and `ghcr_token` as SecureString, `db_host` as String (set by Terraform from the RDS endpoint). Read at boot.
- **Security Groups** – ALB accepts HTTPS only from CloudFront's IP range → EC2 accepts port 5000 only from the ALB → RDS accepts 5432 only from EC2.
- **S3 (media bucket)** – private bucket for site images and video, uploaded by developers. Public access blocked, SSE-S3 encryption, readable only by its CloudFront distribution through Origin Access Control.
- **CloudFront (media)** – serves the media bucket with the `CachingOptimized` policy. A CloudFront Function blocks hotlinking by checking the `Referer` header.



**Boot flow (`scripts/bootstrap.sh`):**

1. Run with `set -euo pipefail`, so the script stops on the first error.
2. Update the OS, install Docker and the AWS CLI.
3. Create a Docker network (`devops-net`).
4. Read `db_host`, `db_password` and `ghcr_token` from SSM Parameter Store.
5. Log in to GHCR and pull the latest app image.
6. Run `alembic upgrade head` in a one-off container (`docker run --rm`) to apply pending migrations.
7. Start the app container with the DB settings, `S3_UPLOADS_BUCKET` and `AWS_DEFAULT_REGION`.

The database and its user are created by Terraform with the RDS instance, so the script doesn't need the Postgres client anymore.

Every new or refreshed instance pulls the latest image and migrates the schema on boot, so there's no manual SQL against RDS.

## CI/CD

GitHub Actions runs on every push and pull request to `main`. Direct pushes to `main` are blocked, so all changes go through a pull request.

1. **Test** – installs dependencies and runs pytest. Runs on pull requests and on `main`, and must pass before a PR can be merged.
2. **Build & push** – builds the Docker image and pushes it to GHCR, tagged `latest` and with the commit SHA. Runs only on `main`.
3. **Deploy** – logs in to AWS with OIDC and starts an ASG instance refresh. New instances are launched and healthy before old ones are terminated, so there's no downtime. Runs only on `main`.

Each step only runs if the previous one passed. Database migrations run during the instance boot, not in the pipeline.

## Roadmap

- [x] Containerized app + Docker Compose local dev
- [x] CI/CD pipeline to GHCR
- [x] EC2 Auto Scaling Group + RDS + Alembic-managed schema
- [x] Application Load Balancer
- [x] CloudFront CDN + AWS WAF
- [x] Automated CI/CD deploy via GitHub OIDC + ASG Instance Refresh
- [x] S3-backed file attachments (GDPR-aware, presigned URLs)
- [x] Terraform (Infrastructure as Code)
- [x] S3-backed media bucket (CloudFront + OAC, hotlink protection)
- [x] Private subnets + NAT Gateway for EC2 and RDS
- [x] Authentication: signup/login with Argon2id and JWT, users only access their own messages
- [x] CloudFront + WAF in front of the ALB managed in Terraform, ALB locked to CloudFront only
- [ ] Authentication on AWS (JWT secret in Parameter Store)
- [ ] Custom AMI with Packer and Ansible
- [ ] CloudWatch logs, dashboard and alarms
