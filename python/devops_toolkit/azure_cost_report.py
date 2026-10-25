"""Summarise Azure spend for a subscription, grouped by resource group or service.

    azure-cost-report --subscription <id> --days 30 --group-by ResourceGroup
    azure-cost-report --subscription <id> --group-by ServiceName --csv > costs.csv

Uses the Cost Management Query API with a token from your `az login` session,
so it needs no SDK and no stored credentials.
"""

import argparse
import csv
import json
import subprocess
import sys
import urllib.request
from datetime import date, timedelta
from typing import Dict, List, Optional, Tuple

API = "https://management.azure.com/subscriptions/{sub}/providers/Microsoft.CostManagement/query?api-version=2023-11-01"


def build_query(days: int, group_by: str, today: Optional[date] = None) -> dict:
    end = today or date.today()
    start = end - timedelta(days=days)
    return {
        "type": "ActualCost",
        "timeframe": "Custom",
        "timePeriod": {"from": start.isoformat(), "to": end.isoformat()},
        "dataset": {
            "granularity": "None",
            "aggregation": {"totalCost": {"name": "Cost", "function": "Sum"}},
            "grouping": [{"type": "Dimension", "name": group_by}],
        },
    }


def parse_rows(response: dict, group_by: str) -> Tuple[List[Tuple[str, float]], str]:
    """Turn the API's column/row format into [(name, cost)] sorted by cost, plus the currency."""
    columns = [c["name"] for c in response["properties"]["columns"]]
    cost_i, name_i = columns.index("Cost"), columns.index(group_by)
    currency_i = columns.index("Currency") if "Currency" in columns else None

    totals: Dict[str, float] = {}
    currency = ""
    for row in response["properties"]["rows"]:
        name = row[name_i] or "(untagged)"
        totals[name] = totals.get(name, 0.0) + float(row[cost_i])
        if currency_i is not None:
            currency = row[currency_i]
    return sorted(totals.items(), key=lambda kv: kv[1], reverse=True), currency


def get_token() -> str:
    out = subprocess.run(  # noqa: S603
        ["az", "account", "get-access-token", "--resource", "https://management.azure.com/", "--output", "json"],  # noqa: S607
        check=True,
        capture_output=True,
        text=True,
    )
    return json.loads(out.stdout)["accessToken"]


def query(subscription: str, body: dict) -> dict:
    req = urllib.request.Request(  # noqa: S310 - fixed https URL
        API.format(sub=subscription),
        data=json.dumps(body).encode(),
        headers={"Authorization": f"Bearer {get_token()}", "Content-Type": "application/json"},
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=60) as resp:  # noqa: S310 - fixed https URL
        return json.load(resp)


def format_report(rows: List[Tuple[str, float]], currency: str, top: int) -> str:
    total = sum(cost for _, cost in rows)
    width = max((len(name) for name, _ in rows[:top]), default=4)
    lines = [f"{'NAME':<{width}}  {'COST':>12}  SHARE"]
    for name, cost in rows[:top]:
        share = cost / total * 100 if total else 0
        lines.append(f"{name:<{width}}  {cost:>12,.2f}  {share:5.1f}%")
    if len(rows) > top:
        rest = sum(cost for _, cost in rows[top:])
        lines.append(f"{f'({len(rows) - top} more)':<{width}}  {rest:>12,.2f}")
    lines.append(f"{'TOTAL':<{width}}  {total:>12,.2f}  {currency}")
    return "\n".join(lines)


def main(argv: Optional[List[str]] = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--subscription", required=True)
    parser.add_argument("--days", type=int, default=30)
    parser.add_argument(
        "--group-by", default="ResourceGroup", choices=["ResourceGroup", "ServiceName", "ResourceLocation"]
    )
    parser.add_argument("--top", type=int, default=15)
    parser.add_argument("--csv", action="store_true")
    args = parser.parse_args(argv)

    rows, currency = parse_rows(query(args.subscription, build_query(args.days, args.group_by)), args.group_by)
    if args.csv:
        writer = csv.writer(sys.stdout)
        writer.writerow([args.group_by, "cost", "currency"])
        writer.writerows((name, f"{cost:.2f}", currency) for name, cost in rows)
    else:
        print(format_report(rows, currency, args.top))
    return 0


if __name__ == "__main__":
    sys.exit(main())
