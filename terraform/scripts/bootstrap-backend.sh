#!/bin/bash

set -e
# a errored out command, stop the script immidiately once any error happens during its execution

BUCKET_NAME="devops-app2-tfstate-364077344467"
TABLE_NAME="devops-app2-tf-lock"
REGION="us-east-2"
# a simple asigning of the names to avoid any syntacs error in typing, Bucket name ends with account ID

if aws s3api head-bucket --bucket "$BUCKET_NAME" 2>/dev/null; then
# head-bucket is an aws API call - asks the AWS if the Bucket with such name exists 
# 2>/dev/null simply prevent showing the error message, as it is solved via if else condition
# if it exists -> type "already exists, skipping", instead of throwwing an error : "BucketAlreadyOwnedByYou"

echo "Bucket $BUCKET_NAME already exists, skipping." 
else 
    aws s3api create-bucket \
        --bucket "$BUCKET_NAME" \
        --region "$REGION" \
        --create-bucket-configuration LocationConstraint="$REGION"

# The actual creation of the Bucket, where LocationConstraint is a quirk to add if it is not us-east-1

aws s3api put-bucket-versioning \
    --bucket "$BUCKET_NAME" \
    --versioning-configuration Status=Enabled
# PUT = > keep old copies instead of overwriting, for a sake of recovery

echo "Created and versioned bucket $BUCKET_NAME."
fi
# a confiration message and if is closed with fi in bash script

if aws dynamodb describe-table --table-name "$TABLE_NAME" --region "$REGION" >/dev/null 2>&1; then
# API call describe-table ask AWS for the table details 
# again >/dev/null 2>&1 throws away the output like error or w.e. 
    echo "Tabel $TABLE_NAME already exists, skipping."
# same pattern as with s3 

else

  aws dynamodb create-table \
    --table-name "$TABLE_NAME" \
    --attribute-definitions AttributeName=LockID,AttributeType=S \
    --key-schema AttributeName=LockID,KeyType=HASH \
    --billing-mode PAY_PER_REQUEST \
    --region "$REGION"
# we are creating the Lock table, Terraform req LockID reserved name with S string values, 
# KeyType=HASH marks the column as a table's primary key, DynamoDB req a primary key column 

    echo "Created Lock table $TABLE_NAME."
fi


