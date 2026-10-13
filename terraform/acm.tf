resource "aws_acm_certificate" "cert" {
  domain_name               = "fatcontract.com"
  subject_alternative_names = ["origin.fatcontract.com"] # just a name we chose for subdomain, like www. or api.
  #40 Our validation code already loops over every name (for_each), so it creates the second validation record automatically. 
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true # makes the new certificate before removing the old one.
  }
}

data "cloudflare_zone" "main" {
  name = "fatcontract.com"
}

resource "cloudflare_record" "cert_validation" {
  for_each = {
    for dvo in aws_acm_certificate.cert.domain_validation_options : dvo.domain_name => {
      name    = dvo.resource_record_name
      content = dvo.resource_record_value
      type    = dvo.resource_record_type
    }
  }

  zone_id = data.cloudflare_zone.main.id
  name    = each.value.name
  content = each.value.content
  type    = each.value.type
  ttl     = 60
}

resource "aws_acm_certificate_validation" "cert" {
  certificate_arn         = aws_acm_certificate.cert.arn
  validation_record_fqdns = [for record in cloudflare_record.cert_validation : record.hostname]
}


# -----------a DNS record pointing the new name at the ALB ----------------

# It’s a DNS record, specifically a CNAME, which works like an alias or nickname.

# It only answers one question: “What’s the real address behind origin.fatcontract.com?”, and the answer is “the ALB, devops-app2-alb-123.us-east-2.elb.amazonaws.com.”
# It never touches the traffic itself. After CloudFront gets the answer, it connects to the ALB directly

resource "cloudflare_record" "origin" {
  zone_id = data.cloudflare_zone.main.id
  name    = "origin"            # now points to ALB, behind CloudFront
  content = aws_lb.app.dns_name # it is how Terraform refers to ALB, the value of it is devops-app2-alb-123...elb.amazonaws.com
  type    = "CNAME"
  proxied = false
  # Cloudflare only acts as DNS here. It must not add its own proxy, or CloudFront would talk to Cloudflare instead of your ALB.
  # Terraform creates the ALB first, AWS gives it a name like devops-app2-alb-1462495311.us-east-2.elb.amazonaws.com, and Terraform puts that real value into the Cloudflare record.
  ttl = 300
}
