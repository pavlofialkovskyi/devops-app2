# Cache policy: nothing cached, but the Authorization header (your JWT) is passed on
resource "aws_cloudfront_cache_policy" "api_no_cache" {
  name        = "devops-app2-api-no-cache"
  min_ttl     = 0
  default_ttl = 0
  max_ttl     = 1

  parameters_in_cache_key_and_forwarded_to_origin {
    cookies_config {
      cookie_behavior = "none"
    }
    query_strings_config {
      query_string_behavior = "all"
    }
    headers_config {
      header_behavior = "whitelist"
      headers {
        items = ["Authorization"]
        # The cache policy: nothing is cached, the same reason as in Phase 3: your API data changes all the time. Authorization is listed on purpose: for GET requests, CloudFront drops that header unless the cache policy includes it, and then your JWT would never reach Flask and every GET /messages would get 401.
      }
    }
  }
}


data "aws_cloudfront_origin_request_policy" "all_viewer_except_host" {
  name = "Managed-AllViewerExceptHostHeader"
}

# AllViewerExceptHostHeader: forwards all other headers (Content-Type, etc.) and query strings like ?limit=50. It skips the Host header, because otherwise CloudFront would ask the ALB for the wrong name, the certificate check would fail, and you’d get 502 errors. We will define this in the Distribution 

resource "aws_cloudfront_distribution" "app" { # a CloudFront itself
  enabled    = true
  comment    = "devops-app2 API in front of the ALB"
  web_acl_id = aws_wafv2_web_acl.app.arn # The line attaches the WAF from waf.tf to this CloudFront distribution.

  origin {
    domain_name = "origin.fatcontract.com"
    origin_id   = "alb-origin"

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "https-only"
      # CloudFront talks to the ALB only over HTTPS, to origin.fatcontract.com. 
      # allowed_methods: all your create, read, update and delete (CRUD) methods pass through, not only GET.
      origin_ssl_protocols = ["TLSv1.2"]
    }
  }

  default_cache_behavior {
    target_origin_id       = "alb-origin"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"]
    cached_methods         = ["GET", "HEAD"]

    cache_policy_id          = aws_cloudfront_cache_policy.api_no_cache.id
    origin_request_policy_id = data.aws_cloudfront_origin_request_policy.all_viewer_except_host.id
    # AWS managed AllViewerExceptHostHeader
    # for example origin_request_policy_id = "b689b0a8-53d0-40ab-baf2-68738e2966ac" 

  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }

  depends_on = [cloudflare_record.origin]
}

output "cloudfront_app_domain" {
  value = aws_cloudfront_distribution.app.domain_name
}