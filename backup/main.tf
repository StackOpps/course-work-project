
locals {
  name = "${var.project_name}-${var.environment}"
}

resource "aws_backup_vault" "dr" {
  name = "${local.name}-dr-vault"
}

# Same protection as the primary vault (Section 3.2): recovery points copied
# here can't be deleted or shortened until the retention window passes.
resource "aws_backup_vault_lock_configuration" "dr" {
  backup_vault_name   = aws_backup_vault.dr.name
  min_retention_days  = var.backup_vault_lock_min_retention_days
  max_retention_days  = var.backup_vault_lock_max_retention_days
  changeable_for_days = var.backup_vault_lock_changeable_for_days
}
