"""Pull month-to-date AWS cost from Cost Explorer and write it to the
dashboard data file docs/index.html reads (published via GitHub Pages).

Unlike the DR/restore-testing recorders, this doesn't append to a growing
history - Cost Explorer already holds the daily numbers, so each run just
overwrites docs/data/cost.json with a fresh pull. The Cost Explorer API only
serves the account's overall spend (it isn't scoped to this project), which
is the honest number to show for a single-tenant testbed account like this
one, but is worth knowing if the same account is ever used for anything else.

Requires the caller to have ce:GetCostAndUsage. Cost Explorer's API is only
served out of us-east-1 regardless of which region the spend happened in.

Usage:
    python scripts/record_cost.py
    python scripts/record_cost.py --days 14 --top 5
"""
from __future__ import annotations

import argparse
import json
from collections import defaultdict
from datetime import date, timedelta
from pathlib import Path

import boto3

from dr_lib import utcnow


def cost_explorer_client():
    # Cost Explorer is a single global endpoint hosted in us-east-1, not a
    # per-region service - unrelated to which region the spend was incurred in.
    return boto3.client("ce", region_name="us-east-1")


def fetch_daily_cost_by_service(days: int) -> list[dict]:
    end = date.today()
    start = end - timedelta(days=days)
    client = cost_explorer_client()

    results = []
    next_token = None
    while True:
        kwargs = dict(
            TimePeriod={"Start": start.isoformat(), "End": end.isoformat()},
            Granularity="DAILY",
            Metrics=["UnblendedCost"],
            GroupBy=[{"Type": "DIMENSION", "Key": "SERVICE"}],
        )
        if next_token:
            kwargs["NextPageToken"] = next_token
        response = client.get_cost_and_usage(**kwargs)
        results.extend(response["ResultsByTime"])
        next_token = response.get("NextPageToken")
        if not next_token:
            break
    return results


def summarise(results_by_time: list[dict], top: int) -> dict:
    daily = []
    by_service_total: dict[str, float] = defaultdict(float)
    grand_total = 0.0

    for period in results_by_time:
        day_total = 0.0
        for group in period["Groups"]:
            service = group["Keys"][0]
            amount = float(group["Metrics"]["UnblendedCost"]["Amount"])
            day_total += amount
            by_service_total[service] += amount
        daily.append({"date": period["TimePeriod"]["Start"], "amount": round(day_total, 2)})
        grand_total += day_total

    by_service = sorted(
        ({"service": s, "amount": round(a, 2)} for s, a in by_service_total.items() if a > 0),
        key=lambda row: row["amount"],
        reverse=True,
    )[:top]

    return {
        "as_of": utcnow().isoformat(),
        "unit": "USD",
        "period_start": results_by_time[0]["TimePeriod"]["Start"] if results_by_time else None,
        "period_end": results_by_time[-1]["TimePeriod"]["End"] if results_by_time else None,
        "total_cost": round(grand_total, 2),
        "daily": daily,
        "by_service": by_service,
    }


def write_cost_data(summary: dict, cost_path: str = "docs/data/cost.json") -> Path:
    path = Path(cost_path)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(summary, indent=2) + "\n")
    return path


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--days", type=int, default=14, help="How many trailing days to pull")
    parser.add_argument("--top", type=int, default=5, help="How many top services to keep")
    parser.add_argument("--cost-path", default="docs/data/cost.json")
    args = parser.parse_args()

    results = fetch_daily_cost_by_service(args.days)
    summary = summarise(results, args.top)
    path = write_cost_data(summary, args.cost_path)

    print(f"Wrote {path}: ${summary['total_cost']} over {len(summary['daily'])} day(s)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
