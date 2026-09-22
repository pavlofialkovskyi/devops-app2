resource "aws_acm_certificate" "cert" {
  domain_name       = "fatcontract.com"
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}

data "cloudflare_zone" "main" {
  name = "fatcontract.com"
}

resource "cloudflare_record" "cert_validation" {
  for_each = {
    for dvo in aws_acm_certificate.cert.domain_validation_options : dvo.domain_name => {
      name  = dvo.resource_record_name
      content = dvo.resource_record_value
      type  = dvo.resource_record_type
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