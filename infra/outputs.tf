output "alb_dns_name" {
  description = "DNS name of the storefront load balancer"
  value       = aws_lb.web.dns_name
}

output "alb_zone_id" {
  description = "Hosted zone ID of the storefront load balancer, for Route 53 alias records"
  value       = aws_lb.web.zone_id
}
