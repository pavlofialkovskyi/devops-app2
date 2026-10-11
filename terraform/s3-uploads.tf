# s3-uploads.tf

# 38 CORS, a preflight to S3, browser asks our s3-upload bucket if requests from my domain fatcontract 
# are allowed to this s3 bucket
resource "aws_s3_bucket_cors_configuration" "uploads" {
  bucket = aws_s3_bucket.uploads.id

  cors_rule {
    allowed_origins = ["https://fatcontract.com"]
    allowed_methods = ["PUT", "GET"]
    allowed_headers = ["*"]    # any request heaaders are allowed
    expose_headers  = ["ETag"] # Frontend state tag
    max_age_seconds = 3000

  }
}


resource "aws_s3_bucket" "uploads" {
  bucket = "devops-app2-uploads-364077344467"

  tags = {
    Name = "devops-app2-uploads"
  }
}

resource "aws_s3_bucket_public_access_block" "uploads" {
  bucket = aws_s3_bucket.uploads.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "uploads" {
  bucket = aws_s3_bucket.uploads.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "uploads" {
  bucket = aws_s3_bucket.uploads.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# GDPR: auto-delete uploaded files after a set retention period. 
# We can adjust "days" to whatever retention period we want, like 30 days
resource "aws_s3_bucket_lifecycle_configuration" "uploads" {
  bucket = aws_s3_bucket.uploads.id

  rule {
    id     = "expire-uploads"
    status = "Enabled"

    filter {}

    expiration {
      days = 30
    }
  }
}



resource "aws_iam_role_policy" "uploads_access" {
  name = "devops-app2-uploads-access"
  role = aws_iam_role.ec2_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = ["s3:PutObject", "s3:GetObject", "s3:DeleteObject"]
        # EC2 role permission to upload/read/delete files in this bucket , only 3 actions, no more
        Resource = "${aws_s3_bucket.uploads.arn}/*"
      }
    ]
  })
}