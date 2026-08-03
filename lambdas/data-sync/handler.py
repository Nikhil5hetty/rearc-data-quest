"""
Lambda handler: rearc-data-sync-{env}
Triggered daily by EventBridge. Syncs BLS data and DataUSA population API → S3.

Local execution:
    python handler.py --local-dir ./data/bls --population-file ./data/population.json
    python handler.py --dry-run --local-dir ./data/bls --population-file ./data/population.json
"""

import json
import logging
import os
import sys

logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] %(message)s")
log = logging.getLogger(__name__)


def _get_aws_region() -> str:
    return os.environ.get("AWS_REGION", os.environ.get("AWS_DEFAULT_REGION", "ap-south-1"))


def run(
    s3_bucket: str | None = None,
    bls_prefix: str = "bls/pr/",
    population_file_key: str = "population/data.json",
    local_bls_dir: str | None = None,
    local_population_file: str | None = None,
    dry_run: bool = False,
) -> dict:
    """
    Core logic callable from Lambda and locally.
    If local_bls_dir / local_population_file are provided, runs without AWS.
    """
    from bls_sync import LocalStorage, S3Storage as BlsS3Storage, sync
    from datausa_api import LocalFileStorage, S3Storage as PopS3Storage, fetch_and_save

    results: dict = {"part1_status": "pending", "part2_status": "pending"}

    # ---- Part 1: BLS sync ----
    log.info("=== Part 1: BLS Sync ===")
    try:
        if local_bls_dir:
            bls_storage = LocalStorage(local_bls_dir)
        else:
            bls_storage = BlsS3Storage(bucket=s3_bucket, prefix=bls_prefix, region=_get_aws_region())
        stats = sync(bls_storage, dry_run=dry_run)
        results["part1_status"] = "success"
        results["part1_result"] = stats
    except Exception as exc:
        log.error("Part 1 failed: %s", exc, exc_info=True)
        results["part1_status"] = "failed"
        results["part1_error"] = str(exc)

    # ---- Part 2: DataUSA population ----
    log.info("=== Part 2: DataUSA Population API ===")
    try:
        if local_population_file:
            pop_storage = LocalFileStorage(local_population_file)
        else:
            pop_storage = PopS3Storage(bucket=s3_bucket, key=population_file_key, region=_get_aws_region())
        result = fetch_and_save(pop_storage, dry_run=dry_run)
        results["part2_status"] = "success"
        results["part2_result"] = result
    except Exception as exc:
        log.error("Part 2 failed: %s", exc, exc_info=True)
        results["part2_status"] = "failed"
        results["part2_error"] = str(exc)

    if results["part1_status"] == "success" and results["part2_status"] == "success":
        results["statusCode"] = 200
        results["message"] = "Data sync completed successfully"
    else:
        results["statusCode"] = 206
        results["message"] = "Data sync completed with errors"

    return results


# ---------------------------------------------------------------------------
# Lambda entry point
# ---------------------------------------------------------------------------

def lambda_handler(event, context):
    log.info("data-sync Lambda starting | event=%s", json.dumps(event))
    result = run(
        s3_bucket=os.environ["S3_BUCKET"],
        bls_prefix=os.environ.get("BLS_PREFIX", "bls/pr/"),
        population_file_key=os.environ.get("POPULATION_FILE_KEY", "population/data.json"),
    )
    log.info("data-sync Lambda complete: %s", json.dumps(result, indent=2))
    return result


# ---------------------------------------------------------------------------
# Local CLI entry point
# ---------------------------------------------------------------------------

if __name__ == "__main__":
    import argparse

    parser = argparse.ArgumentParser(
        description="Run data-sync locally (no AWS required)",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__,
    )
    parser.add_argument(
        "--local-dir", default="./data/bls",
        help="Local directory for BLS data (default: ./data/bls)",
    )
    parser.add_argument(
        "--population-file", default="./data/population.json",
        help="Local file path for population JSON (default: ./data/population.json)",
    )
    parser.add_argument(
        "--s3-bucket", default=None,
        help="S3 bucket name (overrides local mode — uses AWS)",
    )
    parser.add_argument("--dry-run", action="store_true", help="Simulate without writing")

    args = parser.parse_args()

    if args.s3_bucket:
        result = run(s3_bucket=args.s3_bucket, dry_run=args.dry_run)
    else:
        result = run(
            local_bls_dir=args.local_dir,
            local_population_file=args.population_file,
            dry_run=args.dry_run,
        )

    print(json.dumps(result, indent=2))
    sys.exit(0 if result.get("statusCode") == 200 else 1)
