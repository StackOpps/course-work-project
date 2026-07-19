output "vpc_id" {
  value = aws_vpc.main.id
}

output "web_instance_id" {
  value = aws_instance.web.id
}

output "web_private_ip" {
  value = aws_instance.web.private_ip
}

output "rds_endpoint" {
  value     = aws_db_instance.main.endpoint
  sensitive = true
}

output "assets_bucket" {
  value = aws_s3_bucket.assets.id
}

output "alb_dns_name" {
  value = aws_lb.web.dns_name
}

output "alb_zone_id" {
  value = aws_lb.web.zone_id
}

output "app_domain_name" {
  value = var.app_domain_name
}

# Backup vault/role and the detection layer only exist on a primary-region
# apply (see local.is_primary_region) — null on a DR-region apply.
output "backup_vault_name" {
  value = try(aws_backup_vault.main[0].name, null)
}

output "backup_iam_role_arn" {
  value = try(aws_iam_role.backup[0].arn, null)
}

output "composite_alarm_name" {
  value = try(aws_cloudwatch_composite_alarm.site_down[0].alarm_name, null)
}

output "canary_name" {
  value = try(aws_synthetics_canary.storefront[0].name, null)
}

output "cloudtrail_bucket" {
  value = aws_s3_bucket.cloudtrail.id
}

output "alerts_topic_arn" {
  value = aws_sns_topic.alerts.arn
}
