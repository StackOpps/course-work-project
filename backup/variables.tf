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
  description = "Vault Lock minimum retention period recovery points must be kept for, in days"
  type        = number
  default     = 7
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
