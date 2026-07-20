data "aws_route53_zone" "main" {
  name         = var.route53_zone_name
  private_zone = false
}

# Route 53 is the fixed public entry point (Section 3.3): normal traffic
# resolves here to the primary ALB, and the restore workflow repoints this
# same record at the DR ALB once a failover's smoke checks pass. Only
# managed from the primary-region apply, so a DR re-apply of this same
# configuration never fights the primary state over ownership of the record.
resource "aws_route53_record" "app" {
  count = local.is_primary_region ? 1 : 0

  zone_id = data.aws_route53_zone.main.zone_id
  name    = var.app_domain_name
  type    = "A"

  alias {
    name                   = aws_lb.web.dns_name
    zone_id                = aws_lb.web.zone_id
    evaluate_target_health = true
  }
}
