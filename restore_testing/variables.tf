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
  description = "Region the primary backup vault lives in; must match infra/'s var.primary_region"
  type        = string
  default     = "eu-west-2"
}

variable "schedule_expression" {
  description = "Cron expression (AWS Backup format) for how often restore testing runs"
  type        = string
  default     = "cron(0 5 ? * MON *)"
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
