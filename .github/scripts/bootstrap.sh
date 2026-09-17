#!/bin/bash
dnf update -y
dnf install -y docker aws-cli postgresql15
systemctl start docker
systemctl enable docker

# isolate the containers in the network devops-net so that containers in it can have names (ids)
docker network create devops-net

# pull the db pass from the Parameter store in aws ssm
DB_PASSWORD=$(aws ssm get-parameter --name "/devops-app2/db_password" --with-decryption --query "Parameter.Value" --output text --region us-east-2)

# connect to the Postgres in RDS and check if there is a table there, if not - Create Table
PGPASSWORD=$DB_PASSWORD psql -h devops-app2-db.cf6ieyouu1lz.us-east-2.rds.amazonaws.com -U app_user -d postgres -tc "SELECT 1 FROM pg_database WHERE datname = 'devops_app2_db'" | grep -q 1 || \
PGPASSWORD=$DB_PASSWORD psql -h devops-app2-db.cf6ieyouu1lz.us-east-2.rds.amazonaws.com -U app_user -d postgres -c "CREATE DATABASE devops_app2_db;"

# pull the ghcr token from the parameter store in amazon ssm
GHCR_TOKEN=$(aws ssm get-parameter --name "/devops-app2/ghcr_token" --with-decryption --query "Parameter.Value" --output text --region us-east-2)
echo "$GHCR_TOKEN" | docker login ghcr.io -u pavlofialkovskyi --password-stdin

# pull the image of the app from the ghcr
docker pull ghcr.io/pavlofialkovskyi/devops-app2:latest

# create a DB container based on image for temportal usage -> we compare the created table with the one sitting 
# in postgres in RDS via Alembic [last row] and apply changes to the table on aws, like adding a column,
# with NULL values, just for the sake of new table structure
docker run --rm \
  --network devops-net \
  -e DB_HOST=devops-app2-db.cf6ieyouu1lz.us-east-2.rds.amazonaws.com \
  -e DB_PORT=5432 \
  -e DB_NAME=devops_app2_db \
  -e DB_USER=app_user \
  -e DB_PASSWORD=$DB_PASSWORD \
  ghcr.io/pavlofialkovskyi/devops-app2:latest \
  alembic upgrade head

# Start the actual app container
docker run -d \
  --name devops-app2 \
  --network devops-net \
  --restart unless-stopped \
  -e DB_HOST=devops-app2-db.cf6ieyouu1lz.us-east-2.rds.amazonaws.com \
  -e DB_PORT=5432 \
  -e DB_NAME=devops_app2_db \
  -e DB_USER=app_user \
  -e DB_PASSWORD=$DB_PASSWORD \
  -p 5000:5000 \
  ghcr.io/pavlofialkovskyi/devops-app2:latest