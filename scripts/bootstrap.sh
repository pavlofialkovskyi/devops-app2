#!/bin/bash
dnf update -y

systemctl start docker
systemctl enable docker

# isolate the containers in the network devops-net so that containers in it can have names (ids)
docker network create devops-net


# As we provisioned in a LOCAL build for our Docker-compose.yml web app container parameters in the local .ENV we are doing for AWS 
# pulled the db_host ENDPOINT from the Parameter store, which tells 
# the web app container [when created] the name of the Postgres DB on AWS
DB_HOST=$(aws ssm get-parameter --name "/devops-app2/db_host" --query "Parameter.Value" --output text --region us-east-2)


# pulled the db pass from the Parameter store in aws ssm, that will let 
# the web app container [when created] open the lock of the Postgres DB
DB_PASSWORD=$(aws ssm get-parameter --name "/devops-app2/db_password" --with-decryption --query "Parameter.Value" --output text --region us-east-2)


# for Authentication purposes we also grant our EC2 Web app container the JWT-secret that 
# the flask web server will be forwarding to client browser on timed session manner
JWT_SECRET=$(aws ssm get-parameter --name /devops-app2/jwt_secret --with-decryption --query Parameter.Value --output text)


# pull the ghcr token from the parameter store in amazon ssm,  
# that will let EC2 [ON BOOT] to access the IMAGE package in the GHCR that is Private, and pull a new web app container
GHCR_TOKEN=$(aws ssm get-parameter --name "/devops-app2/ghcr_token" --with-decryption --query "Parameter.Value" --output text --region us-east-2)
# Echo feeds the GHCR Token to the Docker login, "--password-stdin" though the pip "|" and not thourgh the command line,
# which keeps the token out of process list and shell history,   
echo "$GHCR_TOKEN" | docker login ghcr.io -u pavlofialkovskyi --password-stdin

# pull the image of the app from the ghcr
docker pull ghcr.io/pavlofialkovskyi/devops-app2:latest

# create a DB container based on image for temportal usage -> we compare the created table with the one sitting 
# in postgres in RDS via Alembic [last row] and apply changes to the table on aws, like adding a column,
# with NULL values, just for the sake of new table structure
docker run --rm \
  --network devops-net \
  -e DB_HOST=$DB_HOST \
  -e DB_PORT=5432 \
  -e DB_NAME=devops_app2_db \
  -e DB_USER=app_user \
  -e DB_PASSWORD=$DB_PASSWORD \
  ghcr.io/pavlofialkovskyi/devops-app2:latest \
  alembic upgrade head

# Start the actual app container
# give it Postgres DB endpoint in AWS DB_HOST, 
# the password to open the Postgres DB DB_PASSWORD
# and the JWT_SECRET for client browser - flask web app server authentication purposes
# important: Wrap variables like "DB_PASSWORD" and "JWT_SECRET" in quotes, it tells BASH that this is one $VAR
# without quotes BASH can split the value at spaces or asterisk *
docker run -d \
  --name devops-app2 \
  --network devops-net \
  --restart unless-stopped \
  -e DB_HOST=$DB_HOST \
  -e DB_PORT=5432 \
  -e DB_NAME=devops_app2_db \
  -e DB_USER=app_user \
  -e DB_PASSWORD="$DB_PASSWORD" \
  -e JWT_SECRET="$JWT_SECRET" \
  -p 5000:5000 \
  ghcr.io/pavlofialkovskyi/devops-app2:latest