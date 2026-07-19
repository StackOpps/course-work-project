variable "aws_region" {
  description = "AWS region to deploy this Terraform configuration's resources into"
  type        = string
  default     = "eu-west-2"
}

variable "primary_region" {
  description = "CraftHaven's normal-operation region; resources that must exist only once (backup plan, canary, alarms) are skipped when aws_region differs, e.g. during a DR failover re-apply"
  type        = string
  default     = "eu-west-2"
}

variable "dr_region" {
  description = "Disaster-recovery region that backup recovery points are copied into"
  type        = string
  default     = "eu-west-1"
}

variable "environment" {
  description = "Deployment environment name (e.g. dev, prod)"
  type        = string
  default     = "dev"
}

variable "project_name" {
  description = "Short project name used as a resource name prefix"
  type        = string
  default     = "crafthaven"
}

variable "vpc_cidr" {
  description = "CIDR block for the CraftHaven VPC"
  type        = string
  default     = "10.20.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets (web tier)"
  type        = list(string)
  default     = ["10.20.0.0/24", "10.20.1.0/24"]
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets (database tier)"
  type        = list(string)
  default     = ["10.20.10.0/24", "10.20.11.0/24"]
}

variable "az_count" {
  description = "Number of availability zones to spread subnets across"
  type        = number
  default     = 2
}

variable "admin_cidr" {
  description = "CIDR allowed administrative access; restrict to office/VPN IP"
  type        = string
  default     = "0.0.0.0/0"
}

variable "instance_type" {
  description = "EC2 instance type for the storefront application server"
  type        = string
  default     = "t3.micro"
}

variable "ec2_ami_id" {
  description = "AMI ID for the web instance; defaults to latest Amazon Linux 2023 if left null"
  type        = string
  default     = null
}

variable "db_engine_version" {
  description = "MySQL engine version for RDS"
  type        = string
  default     = "8.0"
}

variable "db_instance_class" {
  description = "RDS instance class"
  type        = string
  default     = "db.t3.micro"
}

variable "db_allocated_storage" {
  description = "Allocated storage for RDS in GB"
  type        = number
  default     = 20
}

variable "db_name" {
  description = "Initial database name"
  type        = string
  default     = "crafthaven"
}

variable "db_username" {
  description = "Master username for the RDS instance"
  type        = string
  default     = "crafthaven_admin"
}

variable "db_password" {
  description = "Master password for the RDS instance; supply via TF_VAR_db_password or a gitignored tfvars file, never commit it"
  type        = string
  sensitive   = true
}

variable "backup_schedule_cron" {
  description = "Cron expression (AWS Backup format) for the daily backup plan"
  type        = string
  default     = "cron(0 3 * * ? *)"
}

variable "backup_retention_days" {
  description = "How long AWS Backup keeps recovery points before deleting them"
  type        = number
  default     = 35
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

variable "alert_email" {
  description = "Email address that receives CloudWatch/AWS Backup alarm notifications"
  type        = string
}

variable "route53_zone_name" {
  description = "Existing Route 53 public hosted zone CraftHaven's storefront is delegated under, e.g. crafthaven.example"
  type        = string
}

variable "app_domain_name" {
  description = "Full domain name customers use for the storefront, e.g. shop.crafthaven.example"
  type        = string
}

variable "github_owner" {
  description = "GitHub organisation/user that owns the CraftHaven repository, used to target the restore workflow's repository_dispatch API call"
  type        = string
}

variable "github_repo" {
  description = "GitHub repository name that owns the restore workflow, used to target its repository_dispatch API call"
  type        = string
}

variable "github_pat" {
  description = "Fine-grained GitHub personal access token (Contents: read, Actions: write) EventBridge uses to call the repository_dispatch API and start the restore workflow; never commit a real value"
  type        = string
  sensitive   = true
}
