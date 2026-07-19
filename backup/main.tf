# Secondary (DR-region) backup vault. Kept as its own root module, deployed
# by .github/workflows/deploy_dr.yml, rather than folded into infra/: infra's
# backup plan (primary_vault.tf) targets this vault's ARN by name convention
# only, so this stack has no dependency on infra's state and infra has no
# dependency on this stack's outputs.
#
# The vault name must stay in sync with the `dr_vault_name` local infra/
# computes in primary_vault.tf: "${project_name}-${environment}-dr-vault".

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
