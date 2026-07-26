"""Print the ARN of the most recent AWS Backup recovery point for a resource.

Used by dr_failover.yml to find the recovery point to restore the DR
region's RDS instance from (via Terraform's snapshot_identifier), so the DR
rebuild starts from real data with no manual lookup.

Usage:
    python scripts/latest_recovery_point_arn.py \\
        --resource-arn arn:aws:rds:eu-west-2:123456789012:db:crafthaven-dev-db \\
        --region eu-west-1
"""
from __future__ import annotations

import argparse
import sys

from dr_lib import latest_recovery_point


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--resource-arn", required=True)
    parser.add_argument("--region", default=None)
    args = parser.parse_args()

    recovery_point = latest_recovery_point(args.resource_arn, args.region)
    if recovery_point is None:
        print(f"No recovery points found for {args.resource_arn}", file=sys.stderr)
        return 1

    print(recovery_point["RecoveryPointArn"])
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
