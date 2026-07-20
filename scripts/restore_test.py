"""Restore a resource from its most recent AWS Backup recovery point and
measure RTO/RPO against the CraftHaven targets in Dissertation-draft.docx
Section 3.4.

Usage:
    python scripts/restore_test.py \\
        --resource-type RDS \\
        --resource-arn arn:aws:rds:eu-west-2:123456789012:db:crafthaven-dev-db \\
        --vault crafthaven-dev-vault \\
        --iam-role-arn arn:aws:iam::123456789012:role/crafthaven-dev-backup-role
"""
from __future__ import annotations

import argparse
import sys
import time
from typing import Optional

from dr_lib import RecoveryResult, backup_client, latest_recovery_point, utcnow

POLL_INTERVAL_SECONDS = 15
POLL_TIMEOUT_SECONDS = 60 * 30


def start_restore(
    resource_type: str, resource_arn: str, iam_role_arn: str, region: Optional[str]
) -> tuple[str, dict]:
    recovery_point = latest_recovery_point(resource_arn, region)
    if recovery_point is None:
        raise SystemExit(f"No recovery points found for {resource_arn}")

    client = backup_client(region)
    response = client.start_restore_job(
        RecoveryPointArn=recovery_point["RecoveryPointArn"],
        Metadata={},
        IamRoleArn=iam_role_arn,
        ResourceType=resource_type,
    )
    return response["RestoreJobId"], recovery_point


def wait_for_restore(job_id: str, region: Optional[str]) -> bool:
    client = backup_client(region)
    deadline = time.monotonic() + POLL_TIMEOUT_SECONDS
    while time.monotonic() < deadline:
        job = client.describe_restore_job(RestoreJobId=job_id)
        status = job["Status"]
        if status == "COMPLETED":
            return True
        if status in ("ABORTED", "FAILED"):
            return False
        time.sleep(POLL_INTERVAL_SECONDS)
    raise TimeoutError(f"Restore job {job_id} did not complete within {POLL_TIMEOUT_SECONDS}s")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--resource-type", required=True, choices=["EC2", "RDS", "S3"])
    parser.add_argument("--resource-arn", required=True)
    parser.add_argument("--vault", required=True, help="Backup vault name (for logging/labelling only)")
    parser.add_argument("--iam-role-arn", required=True)
    parser.add_argument("--region", default=None)
    parser.add_argument(
        "--failure-triggered-at",
        default=None,
        help="ISO timestamp emitted by failure_simulation.py; defaults to now for a standalone restore test",
    )
    args = parser.parse_args()

    result = RecoveryResult(
        resource_type=args.resource_type,
        resource_id=args.resource_arn,
        failure_triggered_at=args.failure_triggered_at or utcnow().isoformat(),
    )

    job_id, recovery_point = start_restore(
        args.resource_type, args.resource_arn, args.iam_role_arn, args.region
    )
    result.restore_job_id = job_id

    success = wait_for_restore(job_id, args.region)
    if not success:
        result.notes = "Restore job failed or was aborted"
        result.write()
        print(f"Restore FAILED for {args.resource_arn} (job {job_id})", file=sys.stderr)
        return 1

    result.finish(recovery_point_creation_time=recovery_point["CreationDate"])
    out_path = result.write()
    print(
        f"Restore OK from vault {args.vault}: "
        f"RTO={result.rto_seconds:.1f}s RPO={result.rpo_seconds:.1f}s -> {out_path}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
