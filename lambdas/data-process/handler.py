"""
Lambda handler: rearc-data-process-{env}
Triggered by SQS when population/data.json is written to S3.
Runs 3 analytics queries and logs results to CloudWatch.

Local execution (reads from local ./data/ directory):
    python handler.py
    python handler.py --bls-file ./data/bls/pr.data.0.Current --population-file ./data/population.json
"""

import csv
import io
import json
import logging
import os
import sys
from datetime import datetime
from statistics import mean, stdev

import boto3

log = logging.getLogger(__name__)
log.setLevel(logging.INFO)

_s3_client = None


def _get_s3():
    global _s3_client
    if _s3_client is None:
        _s3_client = boto3.client("s3", region_name=os.environ.get("AWS_REGION", "ap-south-1"))
    return _s3_client


# ---------------------------------------------------------------------------
# Data loaders — S3 or local file
# ---------------------------------------------------------------------------

def load_text(*, bucket: str | None = None, key: str | None = None, local_path: str | None = None) -> str:
    if local_path:
        return open(local_path, encoding="utf-8").read()
    return _get_s3().get_object(Bucket=bucket, Key=key)["Body"].read().decode("utf-8")


def load_json(*, bucket: str | None = None, key: str | None = None, local_path: str | None = None) -> dict:
    return json.loads(load_text(bucket=bucket, key=key, local_path=local_path))


# ---------------------------------------------------------------------------
# Query 1: Population mean & stddev 2013-2018
# ---------------------------------------------------------------------------

def query1_population_stats(pop_data: dict) -> dict:
    records = pop_data.get("data", [])
    populations = [int(r["Population"]) for r in records if 2013 <= int(r["Year"]) <= 2018]
    if not populations:
        raise ValueError("No population records found for 2013-2018")

    result = {
        "years": "2013-2018",
        "count": len(populations),
        "mean_population": round(mean(populations), 2),
        "stddev_population": round(stdev(populations), 2) if len(populations) > 1 else 0,
    }
    log.info(
        "Query 1 — Population stats (2013-2018):\n"
        "  Count  : %d\n  Mean   : %s\n  StdDev : %s",
        result["count"],
        f"{result['mean_population']:,.0f}",
        f"{result['stddev_population']:,.0f}",
    )
    return result


# ---------------------------------------------------------------------------
# Query 2: Best year per series_id
# ---------------------------------------------------------------------------

def query2_best_year_per_series(bls_text: str) -> list:
    reader = csv.DictReader(io.StringIO(bls_text), delimiter="\t")
    sums: dict = {}
    for row in reader:
        sid = row.get("series_id", "").strip()
        yr = row.get("year", "").strip()
        val = row.get("value", "").strip()
        if not (sid and yr and val):
            continue
        try:
            sums.setdefault(sid, {})
            sums[sid][int(yr)] = sums[sid].get(int(yr), 0.0) + float(val)
        except ValueError:
            continue

    results = []
    for sid, year_sums in sorted(sums.items()):
        best = max(year_sums, key=lambda y: year_sums[y])
        results.append({"series_id": sid, "best_year": best, "annual_sum": round(year_sums[best], 4)})

    log.info("Query 2 — Best year per series (%d total):\n%s%s",
        len(results),
        "\n".join(f"  {r['series_id']}: year={r['best_year']}, sum={r['annual_sum']}" for r in results[:10]),
        f"\n  ... and {len(results) - 10} more" if len(results) > 10 else "",
    )
    return results


# ---------------------------------------------------------------------------
# Query 3: BLS PRS30006032 / Q01 joined with population
# ---------------------------------------------------------------------------

def query3_bls_population_join(bls_text: str, pop_data: dict) -> list:
    reader = csv.DictReader(io.StringIO(bls_text), delimiter="\t")
    bls_rows: dict = {}
    for row in reader:
        if row.get("series_id", "").strip() == "PRS30006032" and row.get("period", "").strip() == "Q01":
            try:
                bls_rows[int(row["year"].strip())] = float(row["value"].strip())
            except (ValueError, KeyError):
                continue

    pop_by_year = {int(r["Year"]): int(r["Population"]) for r in pop_data.get("data", [])}

    results = [
        {"series_id": "PRS30006032", "year": yr, "period": "Q01",
         "value": bls_rows[yr], "population": pop_by_year.get(yr)}
        for yr in sorted(bls_rows)
    ]
    log.info(
        "Query 3 — BLS PRS30006032 Q01 + population:\n%s",
        "\n".join(f"  {r['year']} | value={r['value']:6.1f} | pop={r['population'] or 'N/A'}" for r in results),
    )
    return results


# ---------------------------------------------------------------------------
# Core logic callable from Lambda and locally
# ---------------------------------------------------------------------------

def run(
    bucket: str | None = None,
    bls_prefix: str = "bls/pr",
    population_key: str = "population/data.json",
    local_bls_file: str | None = None,
    local_population_file: str | None = None,
) -> dict:
    bls_s3_key = f"{bls_prefix.rstrip('/')}/pr.data.0.Current"

    bls_text = load_text(
        bucket=bucket, key=bls_s3_key,
        local_path=local_bls_file,
    )
    pop_data = load_json(
        bucket=bucket, key=population_key,
        local_path=local_population_file,
    )

    results = {
        "statusCode": 200,
        "timestamp": datetime.utcnow().isoformat(),
        "queries_executed": [],
    }

    for label, fn, kwargs in [
        ("Query 1: Population mean/stddev (2013-2018)",   query1_population_stats,    {"pop_data": pop_data}),
        ("Query 2: Best year per series_id",              query2_best_year_per_series, {"bls_text": bls_text}),
        ("Query 3: BLS PRS30006032/Q01 + population",     query3_bls_population_join,  {"bls_text": bls_text, "pop_data": pop_data}),
    ]:
        log.info("Running %s", label)
        try:
            result = fn(**kwargs)
            results["queries_executed"].append({
                "query": label, "status": "success",
                "row_count": len(result) if isinstance(result, list) else None,
                "result": result if not isinstance(result, list) else result[:5],
            })
        except Exception as exc:
            log.error("%s FAILED: %s", label, exc, exc_info=True)
            results["queries_executed"].append({"query": label, "status": "failed", "error": str(exc)})

    return results


# ---------------------------------------------------------------------------
# Lambda entry point
# ---------------------------------------------------------------------------

def lambda_handler(event, context):
    bucket = os.environ.get("S3_BUCKET")
    bls_prefix = os.environ.get("BLS_PREFIX", "bls/pr")
    population_key = os.environ.get("POPULATION_FILE_KEY", "population/data.json")

    log.info("data-process Lambda starting | bucket=%s | event=%s", bucket, json.dumps(event))

    records = event.get("Records", [])
    if not records:
        log.warning("No SQS records in event")
        return {"statusCode": 400, "message": "No SQS records"}

    all_results = []
    for sqs_record in records:
        log.info("Processing SQS message: %s", sqs_record.get("messageId"))
        try:
            body = json.loads(sqs_record.get("body", "{}"))
            s3_records = body.get("Records", [])
            if s3_records:
                evt_bucket = s3_records[0].get("s3", {}).get("bucket", {}).get("name", bucket)
                evt_key = s3_records[0].get("s3", {}).get("object", {}).get("key", population_key)
            else:
                evt_bucket, evt_key = bucket, population_key
        except (json.JSONDecodeError, KeyError, IndexError):
            evt_bucket, evt_key = bucket, population_key

        result = run(bucket=evt_bucket, bls_prefix=bls_prefix, population_key=evt_key)
        all_results.append(result)

    log.info("data-process Lambda complete")
    return {"statusCode": 200, "results": all_results}


# ---------------------------------------------------------------------------
# Local CLI entry point
# ---------------------------------------------------------------------------

if __name__ == "__main__":
    import argparse

    logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] %(message)s")

    parser = argparse.ArgumentParser(
        description="Run data-process analytics locally (no AWS required)",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__,
    )
    parser.add_argument(
        "--bls-file", default="./data/bls/pr.data.0.Current",
        help="Local BLS data file (default: ./data/bls/pr.data.0.Current)",
    )
    parser.add_argument(
        "--population-file", default="./data/population.json",
        help="Local population JSON file (default: ./data/population.json)",
    )
    parser.add_argument(
        "--s3-bucket", default=None,
        help="S3 bucket name (overrides local mode — uses AWS)",
    )
    args = parser.parse_args()

    if args.s3_bucket:
        result = run(bucket=args.s3_bucket)
    else:
        result = run(
            local_bls_file=args.bls_file,
            local_population_file=args.population_file,
        )

    print(json.dumps(result, indent=2))
    sys.exit(0 if result.get("statusCode") == 200 else 1)
