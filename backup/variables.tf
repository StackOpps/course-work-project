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

variable "dr_region" {
  description = "Disaster-recovery region this vault is created in; must match infra/'s var.dr_region"
  type        = string
  default     = "eu-west-1"
}

variable "backup_vault_lock_min_retention_days" {
  description = "Vault Lock minimum retention period recovery points must be kept for, in days. Set to AWS's 1-day floor so the lock is real (nothing, including root, can delete a recovery point before it passes) without permanently blocking this testbed's teardown."
  type        = number
  default     = 1
}

variable "backup_vault_lock_max_retention_days" {
  description = "Vault Lock maximum retention period recovery points may be kept for, in days"
  type        = number
  default     = 90
}

variable "backup_vault_lock_changeable_for_days" {
  description = "Cooling-off period during which the Vault Lock policy can still be deleted, before it becomes immutable"
  type        = number
  default     = 3
}

variable "backup_schedule_cron" {
  description = "Cron expression (AWS Backup format) for the backup plan"
  type        = string
  default     = "cron(0 12 ? * SUN *)" # Weekly at 12:00 UTC on Sunday
}

variable "backup_retention_days" {
  description = "How long AWS Backup keeps recovery points before deleting them"
  type        = number
  default     = 7
}

variable "primary_region" {
  description = "CraftHaven's normal-operation region the primary vault, backup plan, and their monitoring are deployed into; must match infra/'s var.primary_region"
  type        = string
  default     = "eu-west-2"
}

variable "alert_email" {
  description = "Email address that receives AWS Backup job/copy/restore alarm notifications"
  type        = string
  default     = ""
}
