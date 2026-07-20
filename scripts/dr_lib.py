"""Shared helpers for CraftHaven disaster-recovery scripts."""
from __future__ import annotations

import json
import time
from dataclasses import asdict, dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Optional

import boto3

RESULTS_DIR = Path(__file__).resolve().parent.parent / "results"


def utcnow() -> datetime:
    return datetime.now(timezone.utc)


@dataclass
class RecoveryResult:
    resource_type: str
    resource_id: str
    failure_triggered_at: str
    recovery_completed_at: Optional[str] = None
    rto_seconds: Optional[float] = None
    rpo_seconds: Optional[float] = None
    restore_job_id: Optional[str] = None
    success: bool = False
    notes: str = ""

    def finish(self, recovery_point_creation_time: Optional[datetime] = None) -> None:
        end = utcnow()
        self.recovery_completed_at = end.isoformat()
        start = datetime.fromisoformat(self.failure_triggered_at)
        self.rto_seconds = (end - start).total_seconds()
        if recovery_point_creation_time is not None:
            self.rpo_seconds = (start - recovery_point_creation_time).total_seconds()
        self.success = True

    def write(self) -> Path:
        RESULTS_DIR.mkdir(parents=True, exist_ok=True)
        out = RESULTS_DIR / f"{self.resource_type}-{int(time.time())}.json"
        out.write_text(json.dumps(asdict(self), indent=2))
        return out


def backup_client(region: Optional[str] = None):
    return boto3.client("backup", region_name=region)


def latest_recovery_point(resource_arn: str, region: Optional[str] = None) -> Optional[dict]:
    client = backup_client(region)
    points = client.list_recovery_points_by_resource(ResourceArn=resource_arn).get(
        "RecoveryPoints", []
    )
    if not points:
        return None
    return max(points, key=lambda p: p["CreationDate"])
