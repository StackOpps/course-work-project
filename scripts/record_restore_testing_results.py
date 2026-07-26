"""Pull completed jobs from AWS Backup's native restore-testing plan
(restore_testing/) and append the new ones to the dashboard history file
docs/index.html reads, alongside the full-environment dr_failover.yml drills.

Restore testing runs entirely on AWS's own internal schedule (see
restore_testing/variables.tf's schedule_expression) - nothing in this repo
triggers it - so this script is meant to be polled periodically by its own
workflow (record_restore_testing.yml) rather than run inline with a drill.
Idempotent: results already present in --history (matched by restore_job_id)
are skipped, so polling on any cadence just picks up whatever is new.

Two AWS-side assumptions this leans on, unverified against a live account
since this was written without AWS access - if a real run comes back empty
when jobs clearly exist, check these first:
  - DescribeRestoreJob/ListRestoreJobs responses carry a RestoreTestingPlanArn
    field identifying jobs a restore testing plan (not a person) started.
  - list_recovery_points_by_resource can't help work out how old the
    restored point was; describe_recovery_point (used for RPO) needs the
    source vault name, which isn't in the restore job response - --vault-name
    must match the vault restore_testing/main.tf's recovery_point_selection
    actually points at.

Usage:
    python scripts/record_restore_testing_results.py \\
        --region eu-west-1 \\
        --vault-name crafthaven-dev-vault \\
        --history docs/data/history.json
"""
from __future__ import annotations

import argparse
import json
import sys
from dataclasses import asdict
from pathlib import Path
from typing import Optional

from dr_lib import RecoveryResult, backup_client

TERMINAL_STATUSES = {"COMPLETED", "ABORTED", "FAILED"}


def find_plan_arn(client, plan_name: Optional[str]) -> Optional[str]:
    plans = client.list_restore_testing_plans().get("RestoreTestingPlans", [])
    if plan_name:
        plans = [p for p in plans if p["RestoreTestingPlanName"] == plan_name]
    if not plans:
        return None
    return plans[0]["RestoreTestingPlanArn"]


def list_jobs_for_plan(client, plan_arn: str) -> list[dict]:
    jobs: list[dict] = []
    kwargs = {"ByRestoreTestingPlanArn": plan_arn}
    try:
        paginator_kwargs = dict(kwargs)
        next_token = None
        while True:
            if next_token:
                paginator_kwargs["NextToken"] = next_token
            page = client.list_restore_jobs(**paginator_kwargs)
            jobs.extend(page.get("RestoreJobs", []))
            next_token = page.get("NextToken")
            if not next_token:
                break
        return jobs
    except Exception:
        # ByRestoreTestingPlanArn may not be accepted in this boto3/region -
        # fall back to listing everything and filtering client-side.
        jobs = []
        next_token = None
        while True:
            page = client.list_restore_jobs(**({"NextToken": next_token} if next_token else {}))
            jobs.extend(page.get("RestoreJobs", []))
            next_token = page.get("NextToken")
            if not next_token:
                break
        return [j for j in jobs if j.get("RestoreTestingPlanArn") == plan_arn]


def recovery_point_created_at(client, vault_name: str, recovery_point_arn: str):
    try:
        point = client.describe_recovery_point(
            BackupVaultName=vault_name, RecoveryPointArn=recovery_point_arn
        )
        return point["CreationDate"]
    except Exception:
        return None


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--region", default=None)
    parser.add_argument("--vault-name", required=True, help="Vault restore_testing/'s recovery_point_selection reads from")
    parser.add_argument("--plan-name", default=None, help="Restore testing plan name; defaults to the only one in the account/region")
    parser.add_argument("--history", default="docs/data/history.json")
    args = parser.parse_args()

    client = backup_client(args.region)

    plan_arn = find_plan_arn(client, args.plan_name)
    if plan_arn is None:
        print("No restore testing plan found - nothing to record", file=sys.stderr)
        return 0

    jobs = [j for j in list_jobs_for_plan(client, plan_arn) if j["Status"] in TERMINAL_STATUSES]

    history_path = Path(args.history)
    history = json.loads(history_path.read_text()) if history_path.exists() else []
    already_recorded = {r["restore_job_id"] for r in history if r.get("restore_job_id")}

    added = 0
    for job in jobs:
        if job["RestoreJobId"] in already_recorded:
            continue

        result = RecoveryResult(
            resource_type=f"RESTORE_TEST:{job['ResourceType']}",
            resource_id=job.get("CreatedResourceArn") or job["RecoveryPointArn"],
            failure_triggered_at=job["CreationDate"].isoformat(),
            restore_job_id=job["RestoreJobId"],
            notes=f"AWS Backup native restore test ({job['ResourceType']}, plan-driven)",
        )

        if job["Status"] == "COMPLETED":
            recovery_point_created = recovery_point_created_at(client, args.vault_name, job["RecoveryPointArn"])
            result.finish(recovery_point_creation_time=recovery_point_created)
            result.success = job.get("ValidationStatus") in (None, "SUCCESSFUL")
            if not result.success:
                result.notes += f" - validation {job.get('ValidationStatus')}"
        else:
            result.recovery_completed_at = job.get("CompletionDate", job["CreationDate"]).isoformat()
            result.success = False
            result.notes += f" - job {job['Status']}"

        history.append(asdict(result))
        already_recorded.add(job["RestoreJobId"])
        added += 1

    if added:
        history_path.parent.mkdir(parents=True, exist_ok=True)
        history_path.write_text(json.dumps(history, indent=2) + "\n")

    print(f"Recorded {added} new restore-testing result(s) -> {history_path} ({len(history)} total)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
