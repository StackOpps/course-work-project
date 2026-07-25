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


variable "backup_schedule_cron" {
  description = "Cron expression (AWS Backup format) for the daily backup plan"
  type        = string
  default     = "cron(0 * * * ? *)" # 
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
  description = "Email address that receives AWS Backup and Route 53 health check alarm notifications"
  type        = string
  default     = ""
}

variable "app_domain_name" {
  description = "Full domain name customers use for the storefront; the Route 53 health check monitors this over HTTPS. Must match infra/'s var.app_domain_name"
  type        = string
}

variable "github_owner" {
  description = "GitHub organisation/user that owns the CraftHaven repository, used to target the restore workflow's repository_dispatch API call"
  type        = string
  default     = ""
}

variable "github_repo" {
  description = "GitHub repository name that owns the restore workflow, used to target its repository_dispatch API call"
  type        = string
  default     = ""
}

variable "github_pat" {
  description = "Fine-grained GitHub personal access token (Contents: read, Actions: write) EventBridge uses to call the repository_dispatch API and start the restore workflow; never commit a real value"
  type        = string
  sensitive   = true
  default     = ""
}

# variable "backup_vault_lock_min_retention_days" {
#   description = "Vault Lock minimum retention period recovery points must be kept for, in days"
#   type        = number
#   default     = 7
# }

# variable "backup_vault_lock_max_retention_days" {
#   description = "Vault Lock maximum retention period recovery points may be kept for, in days"
#   type        = number
#   default     = 90
# }

# variable "backup_vault_lock_changeable_for_days" {
#   description = "Cooling-off period during which the Vault Lock policy can still be deleted, before it becomes immutable"
#   type        = number
#   default     = 3
# }
