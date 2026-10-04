# CloudFront is the only reader of s3-media, and it reaches S3 through Origin Access Control (OAC) only.
# Hotlinking protection via REFERER


# defining my domain fatcontract.com for hotlinking JS check

variable "allowed_referer_domain" {
  description = "The domain allowed to embed/link media"
  type        = string
  default     = "fatcontract.com"
}


resource "aws_cloudfront_origin_access_control" "media" {
  name                              = "devops-app2-media-oac"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}



# blocking hotlinking, using JS header function
# we search an exact domain name fatcontract.com in the REFERER url, if it finds 
# the substring fatcontact.com than === reuturns -1 , than request is not referred from my own site

resource "aws_cloudfront_function" "block_hotlinking" {
  name    = "devops-app2-media-hotlink-protection"
  runtime = "cloudfront-js-2.0"
  comment = "Blocks requests whose Referer is not my domain, return 403 status"

  code = <<-EOT
    function handler(event) {
      var request = event.request;
      var headers = request.headers;
      var allowedDomain = "${var.allowed_referer_domain}";

      var referer = headers.referer ? headers.referer.value : "";

      if (referer.indexOf(allowedDomain) === -1) {
        return {
          statusCode: 403,
          statusDescription: "Forbidden",
          body: {
            encoding: "text",
            data: "Hotlinking is not allowed."
          }
        };
      }

      return request;
    }
  EOT
}


resource "aws_cloudfront_distribution" "media" {
  enabled             = true
  default_root_object = "index.html"

  origin {
    domain_name              = aws_s3_bucket.media.bucket_regional_domain_name
    origin_id                = "media-s3-origin"
# just a random tag for s3, we use it in cache behavior later
    origin_access_control_id = aws_cloudfront_origin_access_control.media.id
  }


  default_cache_behavior {
    target_origin_id       = "media-s3-origin"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD"]
    cached_methods          = ["GET", "HEAD"]

# The modern approach referencing an AWS Managed Cache Policy 
# by its ID, like CachingOptimized (a policy AWS maintains to be tuned well for static assets like images)

   cache_policy_id = "658327ea-f89d-4fab-a63d-7e88639e58f6"
  
    function_association {
      event_type   = "viewer-request"
      function_arn = aws_cloudfront_function.block_hotlinking.arn
    }
  }


  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }
}



# policy: the only identity that can read from this S3 is Cloudfront

resource "aws_s3_bucket_policy" "media" {
  bucket = aws_s3_bucket.media.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AllowCloudFrontServicePrincipalReadOnly"
        Effect    = "Allow"
        Principal = { Service = "cloudfront.amazonaws.com" }
        Action    = "s3:GetObject"
        Resource  = "${aws_s3_bucket.media.arn}/*"
        Condition = {
          StringEquals = {
            "AWS:SourceArn" = aws_cloudfront_distribution.media.arn
          }
        }
      }
    ]
  })
}