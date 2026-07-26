"""Delete every recovery point in an AWS Backup vault.

AWS Backup refuses to delete a vault that still holds recovery points, and
Terraform has no force_destroy equivalent for aws_backup_vault, so the
scheduled destroy workflow needs this to run against both the primary and DR
vaults before `terraform destroy` touches backup/ - otherwise every run
fails at the vault resource.

Usage:
    python scripts/empty_backup_vault.py \\
        --vault-arn arn:aws:backup:eu-west-1:123456789012:backup-vault:crafthaven-dev-dr-vault
"""
from __future__ import annotations

import argparse
import sys
import time

from dr_lib import backup_client


def parse_vault_arn(vault_arn: str) -> tuple[str, str]:
    # arn:aws:backup:<region>:<account_id>:backup-vault:<name>
    parts = vault_arn.split(":", 6)
    if len(parts) < 7 or parts[5] != "backup-vault":
        raise ValueError(f"Not a backup vault ARN: {vault_arn}")
    return parts[3], parts[6]


def delete_all_recovery_points(vault_arn: str, poll_seconds: int = 15, timeout_seconds: int = 600) -> None:
    region, vault_name = parse_vault_arn(vault_arn)
    client = backup_client(region)

    paginator = client.get_paginator("list_recovery_points_by_backup_vault")
    deleted = 0
    for page in paginator.paginate(BackupVaultName=vault_name):
        for point in page.get("RecoveryPoints", []):
            if point["Status"] in ("DELETING", "EXPIRED"):
                continue
            client.delete_recovery_point(
                BackupVaultName=vault_name,
                RecoveryPointArn=point["RecoveryPointArn"],
            )
            deleted += 1
    print(f"{vault_name}: requested deletion of {deleted} recovery point(s)")

    # Deletion is async, and terraform destroy will fail immediately if the
    # vault still reports recovery points, so wait for it to actually empty.
    waited = 0
    while waited < timeout_seconds:
        remaining = client.list_recovery_points_by_backup_vault(
            BackupVaultName=vault_name
        ).get("RecoveryPoints", [])
        if not remaining:
            print(f"{vault_name}: empty")
            return
        time.sleep(poll_seconds)
        waited += poll_seconds

    raise TimeoutError(
        f"{vault_name}: still has recovery points after {timeout_seconds}s"
    )


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--vault-arn", required=True)
    args = parser.parse_args()

    delete_all_recovery_points(args.vault_arn)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
