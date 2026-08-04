"""Shared helpers for CraftHaven disaster-recovery scripts."""
from __future__ import annotations

import json
from dataclasses import asdict, dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Optional

import boto3


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


def backup_client(region: Optional[str] = None):
    return boto3.client("backup", region_name=region)


def append_history(result: RecoveryResult, history_path: str = "docs/data/history.json") -> Path:
    """Append a result to the dashboard history file docs/index.html reads
    (published via GitHub Pages), shared by every script that records a
    drill or test so the schema stays in one place."""
    path = Path(history_path)
    path.parent.mkdir(parents=True, exist_ok=True)
    history = json.loads(path.read_text()) if path.exists() else []
    history.append(asdict(result))
    path.write_text(json.dumps(history, indent=2) + "\n")
    return path
