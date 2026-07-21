resource "aws_acm_certificate" "web" {
  domain_name       = var.app_domain_name
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }

  tags = { Name = "${local.name}-cert" }
}

resource "aws_route53_record" "web_cert_validation" {
  zone_id         = data.aws_route53_zone.main.zone_id
  name            = tolist(aws_acm_certificate.web.domain_validation_options)[0].resource_record_name
  type            = tolist(aws_acm_certificate.web.domain_validation_options)[0].resource_record_type
  records         = [tolist(aws_acm_certificate.web.domain_validation_options)[0].resource_record_value]
  ttl             = 60
  allow_overwrite = true
  depends_on      = [aws_acm_certificate.web]
}

resource "aws_acm_certificate_validation" "web" {
  certificate_arn         = aws_acm_certificate.web.arn
  validation_record_fqdns = [aws_route53_record.web_cert_validation.fqdn]
}
