# AWS Backup's native restore-testing feature: regularly restores a sample
# recovery point and reports whether it succeeded, independent of the
# scripts/restore_test.py path that measures RTO/RPO for Chapter 4's
# evaluation. Kept as its own root module so its restore jobs can never
# create a dependency cycle with infra/'s backup plan (infra creates the
# vault and recovery points; this stack only reads them by ARN convention).

locals {
  name = "${var.project_name}-${var.environment}"

  # Matches the vault infra/primary_vault.tf creates and the role it grants
  # AWS Backup, both referenced here by name convention only — this stack
  # has no Terraform dependency on infra/'s state.
  dr_vault_arn    = "arn:aws:backup:${var.aws_region}:${data.aws_caller_identity.current.account_id}:backup-vault:${local.name}-vault"
  backup_role_arn = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/${local.name}-backup-role"
}

resource "aws_backup_restore_testing_plan" "main" {
  name                = replace("${local.name}-restore-test", "-", "_")
  schedule_expression = var.schedule_expression
  start_window_hours  = var.start_window_hours

  recovery_point_selection {
    algorithm             = "LATEST_WITHIN_WINDOW"
    include_vaults        = [local.dr_vault_arn]
    recovery_point_types  = ["SNAPSHOT"]
    selection_window_days = 7
  }
}

resource "aws_backup_restore_testing_selection" "rds" {
  name                      = "rds"
  restore_testing_plan_name = aws_backup_restore_testing_plan.main.name
  protected_resource_type   = "RDS"
  iam_role_arn              = local.backup_role_arn
  protected_resource_arns   = ["*"]
  validation_window_hours   = var.validation_window_hours
}

resource "aws_backup_restore_testing_selection" "ec2" {
  name                      = "ec2"
  restore_testing_plan_name = aws_backup_restore_testing_plan.main.name
  protected_resource_type   = "EC2"
  iam_role_arn              = local.backup_role_arn
  protected_resource_arns   = ["*"]
  validation_window_hours   = var.validation_window_hours
}
