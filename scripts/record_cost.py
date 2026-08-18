"""Pull month-to-date AWS cost from Cost Explorer and write it to the
dashboard data file docs/index.html reads (published via GitHub Pages).

Unlike the DR/restore-testing recorders, this doesn't append to a growing
history - Cost Explorer already holds the daily numbers, so each run just
overwrites docs/data/cost.json with a fresh pull. The account is
single-tenant, so whole-account spend (by_service, "total_cost") is still
an honest number for this project - but infra/, backup/, and
restore_testing/ each tag their resources with a Stack default_tag
(infra/providers.tf, backup/providers.tf, restore_testing/providers.tf), so
spend can also be split per workload (by_workload) instead of only ever
reported as one lump sum.

Requires the caller to have ce:GetCostAndUsage, ce:ListCostAllocationTags,
and ce:UpdateCostAllocationTagsStatus. Cost Explorer's API is only served
out of us-east-1 regardless of which region the spend happened in.

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
from botocore.exceptions import ClientError

from dr_lib import utcnow


def cost_explorer_client():
    # Cost Explorer is a single global endpoint hosted in us-east-1, not a
    # per-region service - unrelated to which region the spend was incurred in.
    return boto3.client("ce", region_name="us-east-1")


def fetch_daily_cost(days: int, group_by: dict) -> list[dict]:
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
            GroupBy=[group_by],
        )
        if next_token:
            kwargs["NextPageToken"] = next_token
        response = client.get_cost_and_usage(**kwargs)
        results.extend(response["ResultsByTime"])
        next_token = response.get("NextPageToken")
        if not next_token:
            break
    return results


def fetch_daily_cost_by_service(days: int) -> list[dict]:
    return fetch_daily_cost(days, {"Type": "DIMENSION", "Key": "SERVICE"})


# infra/, backup/, and restore_testing/ each set a Stack default_tag
# (infra/providers.tf etc.) naming their workload, so this is the same
# per-day/per-day breakdown as fetch_daily_cost_by_service but split by
# workload instead of AWS service.
def fetch_daily_cost_by_workload(days: int, tag_key: str = "Stack") -> list[dict]:
    return fetch_daily_cost(days, {"Type": "TAG", "Key": tag_key})


# Cost Explorer only splits spend by a tag once that tag has been activated
# as a cost allocation tag - a one-time, account-level setting distinct from
# the tag existing on resources. Not retroactive (spend incurred before
# activation stays out of by_workload) and can take up to 24h to appear
# after activation, so a first run after this starts may show an
# empty/small by_workload next to a normal-looking total_cost.
def ensure_cost_allocation_tag_active(tag_key: str = "Stack") -> None:
    client = cost_explorer_client()
    known = client.list_cost_allocation_tags(TagKeys=[tag_key]).get("CostAllocationTagsList", [])
    if not known:
        print(f"'{tag_key}' not yet known to Cost Explorer as a cost allocation tag candidate - it's discovered from billed usage, so this can lag behind resources actually being tagged.")
        return
    if known[0]["Status"] == "Active":
        return
    client.update_cost_allocation_tags_status(CostAllocationTagsStatus=[{"TagKey": tag_key, "Status": "Active"}])
    print(f"Activated '{tag_key}' as a cost allocation tag (can take up to 24h to appear in by_workload).")


def _top_rows(results_by_time: list[dict], label_key: str, top: int, label_map=lambda k: k) -> list[dict]:
    totals: dict[str, float] = defaultdict(float)
    for period in results_by_time:
        for group in period["Groups"]:
            totals[label_map(group["Keys"][0])] += float(group["Metrics"]["UnblendedCost"]["Amount"])
    return sorted(
        ({label_key: k, "amount": round(v, 2)} for k, v in totals.items() if v > 0),
        key=lambda row: row["amount"],
        reverse=True,
    )[:top]


def summarise(results_by_time: list[dict], workload_results_by_time: list[dict], top: int) -> dict:
    daily = []
    grand_total = 0.0

    for period in results_by_time:
        day_total = sum(
            float(group["Metrics"]["UnblendedCost"]["Amount"]) for group in period["Groups"]
        )
        daily.append({"date": period["TimePeriod"]["Start"], "amount": round(day_total, 2)})
        grand_total += day_total

    by_service = _top_rows(results_by_time, "service", top)
    by_workload = _top_rows(
        workload_results_by_time,
        "workload",
        top,
        # Cost Explorer's tag GroupBy key comes back as "Stack$infra"; spend
        # with no Stack tag at all (e.g. Tax) comes back as "Stack$" (or is
        # dropped by the amount > 0 filter in _top_rows if it's zero).
        label_map=lambda k: k.split("$", 1)[1] or "Untagged" if "$" in k else k,
    )

    return {
        "as_of": utcnow().isoformat(),
        "unit": "USD",
        "period_start": results_by_time[0]["TimePeriod"]["Start"] if results_by_time else None,
        "period_end": results_by_time[-1]["TimePeriod"]["End"] if results_by_time else None,
        "total_cost": round(grand_total, 2),
        "daily": daily,
        "by_service": by_service,
        "by_workload": by_workload,
    }


def write_cost_data(summary: dict, cost_path: str = "docs/data/cost.json") -> Path:
    path = Path(cost_path)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(summary, indent=2) + "\n")
    return path


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--days", type=int, default=14, help="How many trailing days to pull")
    parser.add_argument("--top", type=int, default=5, help="How many top services/workloads to keep")
    parser.add_argument("--cost-path", default="docs/data/cost.json")
    args = parser.parse_args()

    results = fetch_daily_cost_by_service(args.days)

    # Additive on top of by_service, which has worked without these two
    # extra permissions until now - degrade to an empty by_workload rather
    # than losing the whole poll if the CI role hasn't been granted
    # ce:ListCostAllocationTags/ce:UpdateCostAllocationTagsStatus yet, or if
    # the tag genuinely isn't active yet.
    workload_results: list[dict] = []
    try:
        ensure_cost_allocation_tag_active()
        workload_results = fetch_daily_cost_by_workload(args.days)
    except ClientError as exc:
        print(f"Skipping by_workload this run: {exc}")

    summary = summarise(results, workload_results, args.top)
    path = write_cost_data(summary, args.cost_path)

    print(f"Wrote {path}: ${summary['total_cost']} over {len(summary['daily'])} day(s)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
