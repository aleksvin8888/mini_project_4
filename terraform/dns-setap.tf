
resource "cloudflare_record" "frontend_subdomain" {
  depends_on = [aws_cloudfront_distribution.frontend_distribution]
  zone_id = data.cloudflare_zones.main_zones.zones[0].id
  name    = "${var.frontend_subdomain}.${var.main_domain_name}"
  type    = "CNAME"
  value   = aws_cloudfront_distribution.frontend_distribution.domain_name
}

resource "cloudflare_record" "api_rds_record" {
  depends_on = [aws_alb.api_alb]
  zone_id = data.cloudflare_zones.main_zones.zones[0].id
  name    = "${var.rds_subdomain}.${var.main_domain_name}"
  type    = "CNAME"
  value   = aws_alb.api_alb.dns_name
}

resource "cloudflare_record" "api_redis_record" {
  depends_on = [aws_alb.api_alb]
  zone_id = data.cloudflare_zones.main_zones.zones[0].id
  name    = "${var.redis_subdomain}.${var.main_domain_name}"
  type    = "CNAME"
  value   = aws_alb.api_alb.dns_name
}

resource "aws_acm_certificate" "frontend_cert" {
  domain_name       = "*.${var.main_domain_name}"

  validation_method = "DNS"

  tags = {
    Name = "FrontendCertificate"
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "cloudflare_record" "acm_validation" {
  for_each = {
    for dvo in aws_acm_certificate.frontend_cert.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  zone_id = data.cloudflare_zones.main_zones.zones[0].id
  name    = each.value.name
  type    = each.value.type
  value   = each.value.record
}


resource "aws_acm_certificate_validation" "frontend_cert_validation" {
  certificate_arn         = aws_acm_certificate.frontend_cert.arn
  validation_record_fqdns = [for record in cloudflare_record.acm_validation : record.name]

  depends_on = [cloudflare_record.acm_validation]
}

data "cloudflare_zones" "main_zones" {
  filter {
    name = var.main_domain_name
  }
}

