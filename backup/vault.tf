
locals {
  name = "${var.project_name}-${var.environment}"
  backup_polic_arns = [
    "arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForBackup",
    "arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForRestores",
    "arn:aws:iam::aws:policy/AWSBackupServiceRolePolicyForS3Backup"
  ]
}
data "aws_iam_policy" "backup_policy" {
  provider = aws.primary
  for_each = toset(local.backup_polic_arns)
  arn      = each.value

}
resource "aws_backup_vault" "dr" {
  provider = aws.dr
  name     = "${local.name}-dr-vault"
}


resource "aws_backup_vault_lock_configuration" "dr" {
  provider            = aws.dr
  backup_vault_name   = aws_backup_vault.dr.name
  min_retention_days  = var.backup_vault_lock_min_retention_days
  max_retention_days  = var.backup_vault_lock_max_retention_days
  changeable_for_days = var.backup_vault_lock_changeable_for_days
}

resource "aws_backup_vault" "primary" {
  provider = aws.primary
  name     = "${local.name}-vault"
}

resource "aws_backup_vault_lock_configuration" "main" {
  provider = aws.primary

  backup_vault_name   = aws_backup_vault.primary.name
  min_retention_days  = var.backup_vault_lock_min_retention_days
  max_retention_days  = var.backup_vault_lock_max_retention_days
  changeable_for_days = var.backup_vault_lock_changeable_for_days
}

resource "aws_iam_role" "backup" {
  provider = aws.primary

  name = "${local.name}-backup-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "backup.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "backup_policy_attachment" {
  for_each = data.aws_iam_policy.backup_policy
  provider = aws.primary

  role       = aws_iam_role.backup.name
  policy_arn = each.value.arn
}


resource "aws_backup_plan" "main" {
  provider = aws.primary

  name = "${local.name}-backup-plan"

  rule {
    rule_name         = "hourly"
    target_vault_name = aws_backup_vault.primary.name
    schedule          = var.backup_schedule_cron
    start_window      = 60
    completion_window = 180

    lifecycle {
      delete_after = var.backup_retention_days
    }

    copy_action {
      destination_vault_arn = aws_backup_vault.dr.arn

      lifecycle {
        delete_after = var.backup_retention_days
      }
    }
  }
}

# Tag-based selection: EC2 (with attached EBS), RDS, and the assets bucket
# are all tagged Backup=true, so a new resource joins the backup plan just by
# carrying the tag — no need to touch the plan when the workload changes.
resource "aws_backup_selection" "main" {
  provider = aws.primary

  name         = "${local.name}-backup-selection"
  plan_id      = aws_backup_plan.main.id
  iam_role_arn = aws_iam_role.backup.arn

  selection_tag {
    type  = "STRINGEQUALS"
    key   = "Backup"
    value = "true"
  }
}
