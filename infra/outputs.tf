output "alb_dns_name" {
  description = "DNS name of the storefront load balancer"
  value       = aws_lb.web.dns_name
}

output "alb_zone_id" {
  description = "Hosted zone ID of the storefront load balancer, for Route 53 alias records"
  value       = aws_lb.web.zone_id
}

output "restored_recovery_point_created_at" {
  description = "Creation timestamp of the AWS Backup recovery point this apply restored RDS from; null for a normal (non-DR) apply"
  value       = local.is_dr_region ? data.aws_db_snapshot.latest[0].snapshot_create_time : null
}
