variable "project_name" {
  description = "Short project name used as a resource name prefix; must match infra/"
  type        = string
  default     = "crafthaven"
}

variable "environment" {
  description = "Deployment environment name (e.g. dev, prod); must match infra/"
  type        = string
  default     = "dev"
}

variable "aws_region" {
  description = "Region the DR backup vault lives in; must match backup/'s var.dr_region"
  type        = string
  default     = "eu-west-1"
}

variable "schedule_expression" {
  description = "Cron expression (AWS Backup format) for how often restore testing runs"
  type        = string
  # Hourly is the shortest interval AWS Backup's scheduler allows for restore
  # testing plans (same 1-hour floor as backup plan rules) - anything more
  # frequent is rejected service-side, not a Terraform-level restriction.
  # day-of-month is "?" because AWS's 6-field cron requires exactly one of
  # day-of-month/day-of-week to be "?" when the other is a value.
  default = "cron(0 * ? * * *)"
}

variable "start_window_hours" {
  description = "Hours restore testing has to start a restore job once triggered"
  type        = number
  default     = 24
}

variable "validation_window_hours" {
  description = "Hours available to run validation scripts against a completed test restore"
  type        = number
  default     = 24
}
