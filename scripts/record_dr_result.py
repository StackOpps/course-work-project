"""Record a completed DR event as a RecoveryResult and append it to the
dashboard history file docs/index.html reads (published via GitHub Pages),
so every dr_failover.yml run leaves a permanent, plottable RTO/RPO record
instead of vanishing with the workflow log once it scrolls off Actions.

Usage:
    python scripts/record_dr_result.py \\
        --resource-type ENV \\
        --resource-id crafthaven.example.com \\
        --failure-triggered-at 2026-07-26T09:00:00+00:00 \\
        --recovery-point-created-at 2026-07-26T02:00:00+00:00 \\
        --restore-job-id abc123 \\
        --notes "Automated DR failover drill"
"""
from __future__ import annotations

import argparse
import json
from dataclasses import asdict
from datetime import datetime
from pathlib import Path

from dr_lib import RecoveryResult, utcnow


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--resource-type", required=True)
    parser.add_argument("--resource-id", required=True)
    parser.add_argument("--failure-triggered-at", required=True)
    parser.add_argument("--recovery-point-created-at", default=None)
    parser.add_argument("--restore-job-id", default=None)
    parser.add_argument("--notes", default="")
    parser.add_argument(
        "--failed", action="store_true", help="Record this as a failed drill instead of a success"
    )
    parser.add_argument("--history", default="docs/data/history.json")
    args = parser.parse_args()

    result = RecoveryResult(
        resource_type=args.resource_type,
        resource_id=args.resource_id,
        failure_triggered_at=args.failure_triggered_at,
        restore_job_id=args.restore_job_id,
        notes=args.notes,
    )

    if args.failed:
        result.recovery_completed_at = utcnow().isoformat()
        result.success = False
    else:
        recovery_point_created = (
            datetime.fromisoformat(args.recovery_point_created_at)
            if args.recovery_point_created_at
            else None
        )
        result.finish(recovery_point_creation_time=recovery_point_created)

    history_path = Path(args.history)
    history_path.parent.mkdir(parents=True, exist_ok=True)
    history = json.loads(history_path.read_text()) if history_path.exists() else []
    history.append(asdict(result))
    history_path.write_text(json.dumps(history, indent=2) + "\n")

    print(f"Recorded {args.resource_type} drill -> {history_path} ({len(history)} total)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
