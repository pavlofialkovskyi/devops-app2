# Static media bucket (images/videos) for the public-facing frontend page. 
# Developers upload manually with their own IAM credentials. 
# Encryption 


resource "aws_s3_bucket" "media" {
  bucket = "devops-app2-media-364077344467"

  tags = {
    Name = "devops-app2-media"
  }
}


# no Public access, blocks true!!! 

resource "aws_s3_bucket_public_access_block" "media" {
  bucket = aws_s3_bucket.media.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}


resource "aws_s3_bucket_ownership_controls" "media" {
  bucket = aws_s3_bucket.media.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

# automatic encryption to protect the data when someone aks S3 for the file though the API/network

resource "aws_s3_bucket_server_side_encryption_configuration" "media" {
  bucket = aws_s3_bucket.media.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}


