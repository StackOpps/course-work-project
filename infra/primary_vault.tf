# Guarded to the primary region only: there is exactly one backup plan for
# the workload, regardless of which region this configuration happens to be
# applied against (see local.is_primary_region in network.tf). The DR-region
# vault it copies recovery points into lives in the separate backup/ stack.

resource "aws_backup_vault" "main" {
  count = local.is_primary_region ? 1 : 0

  name = "${local.name}-vault"
}

# Governance mode: recovery points can't be deleted or shortened by anyone,
# including root, until the retention window passes — the defence against
# ransomware reaching the backup vault that Chapter 2 argues access control
# alone can't provide.
resource "aws_backup_vault_lock_configuration" "main" {
  count = local.is_primary_region ? 1 : 0

  backup_vault_name   = aws_backup_vault.main[0].name
  min_retention_days  = var.backup_vault_lock_min_retention_days
  max_retention_days  = var.backup_vault_lock_max_retention_days
  changeable_for_days = var.backup_vault_lock_changeable_for_days
}

resource "aws_iam_role" "backup" {
  count = local.is_primary_region ? 1 : 0

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

resource "aws_iam_role_policy_attachment" "backup" {
  count = local.is_primary_region ? 1 : 0

  role       = aws_iam_role.backup[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForBackup"
}

resource "aws_iam_role_policy_attachment" "restore" {
  count = local.is_primary_region ? 1 : 0

  role       = aws_iam_role.backup[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForRestores"
}

resource "aws_iam_role_policy_attachment" "s3_backup" {
  count = local.is_primary_region ? 1 : 0

  role       = aws_iam_role.backup[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForS3Backup"
}

resource "aws_iam_role_policy_attachment" "s3_restore" {
  count = local.is_primary_region ? 1 : 0

  role       = aws_iam_role.backup[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForS3Restore"
}

# Matches the vault name the separate backup/ stack creates in var.dr_region,
# so the copy_action below can target it by ARN without a remote-state
# dependency between the two stacks (backup/example.tf's note on why they're
# kept separate applies here too).
locals {
  dr_vault_name = "${local.name}-dr-vault"
  dr_vault_arn  = "arn:aws:backup:${var.dr_region}:${data.aws_caller_identity.current.account_id}:backup-vault:${local.dr_vault_name}"
}

resource "aws_backup_plan" "main" {
  count = local.is_primary_region ? 1 : 0

  name = "${local.name}-backup-plan"

  rule {
    rule_name         = "daily"
    target_vault_name = aws_backup_vault.main[0].name
    schedule          = var.backup_schedule_cron
    start_window      = 60
    completion_window = 180

    lifecycle {
      delete_after = var.backup_retention_days
    }

    # Every recovery point is copied into the DR-region vault as soon as it's
    # created, so restores never depend on the primary region being healthy
    # (Section 3.3: "recovery points ... automatically copied to a second
    # locked vault in the DR region").
    copy_action {
      destination_vault_arn = local.dr_vault_arn

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
  count = local.is_primary_region ? 1 : 0

  name         = "${local.name}-backup-selection"
  plan_id      = aws_backup_plan.main[0].id
  iam_role_arn = aws_iam_role.backup[0].arn

  selection_tag {
    type  = "STRINGEQUALS"
    key   = "Backup"
    value = "true"
  }
}
