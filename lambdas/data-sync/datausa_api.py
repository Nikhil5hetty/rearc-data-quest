"""
DataUSA Population API — Part 2
Fetches US population by year from the DataUSA API and saves the result
to an S3 object (production) or a local file (dev/test).
"""

import json
import logging
import os
from abc import ABC, abstractmethod
from pathlib import Path

import requests

DATAUSA_API_URL = (
    "https://honolulu-api.datausa.io/tesseract/data.jsonrecords?"
    "cube=acs_yg_total_population_1&drilldowns=Year%2CNation&locale=en&measures=Population"
)

log = logging.getLogger(__name__)


# ---------------------------------------------------------------------------
# Storage abstraction
# ---------------------------------------------------------------------------

class StorageBackend(ABC):
    @abstractmethod
    def write_json(self, data: dict, dry_run: bool = False) -> None: ...
    @abstractmethod
    def describe(self) -> str: ...


class LocalFileStorage(StorageBackend):
    def __init__(self, filepath: str) -> None:
        self.path = Path(filepath)
        self.path.parent.mkdir(parents=True, exist_ok=True)

    def write_json(self, data: dict, dry_run: bool = False) -> None:
        text = json.dumps(data, indent=2)
        if dry_run:
            log.info("[DRY RUN] Would write %d bytes to %s", len(text), self.path)
        else:
            self.path.write_text(text)
            log.info("Written %d bytes → %s", len(text), self.path)

    def describe(self) -> str:
        return str(self.path.resolve())


class S3Storage(StorageBackend):
    def __init__(self, bucket: str, key: str, region: str) -> None:
        import boto3
        self.bucket = bucket
        self.key = key
        self.region = region
        self._client = boto3.client("s3", region_name=region)

    def write_json(self, data: dict, dry_run: bool = False) -> None:
        text = json.dumps(data, indent=2)
        if dry_run:
            log.info("[DRY RUN] Would upload %d bytes to s3://%s/%s", len(text), self.bucket, self.key)
        else:
            self._client.put_object(
                Bucket=self.bucket, Key=self.key,
                Body=text.encode("utf-8"), ContentType="application/json",
            )
            log.info("Uploaded %d bytes → s3://%s/%s", len(text), self.bucket, self.key)

    def describe(self) -> str:
        return f"s3://{self.bucket}/{self.key}"


# ---------------------------------------------------------------------------
# Core logic
# ---------------------------------------------------------------------------

def fetch_population_data() -> dict:
    log.info("Fetching population data from DataUSA API")
    response = requests.get(DATAUSA_API_URL, timeout=30)
    response.raise_for_status()
    data = response.json()
    record_count = len(data.get("data", []))
    log.info("API returned %d record(s)", record_count)
    return data


def fetch_and_save(storage: StorageBackend, dry_run: bool = False) -> dict:
    log.info("DataUSA fetch → %s%s", storage.describe(), "  [DRY RUN]" if dry_run else "")
    data = fetch_population_data()
    storage.write_json(data, dry_run=dry_run)
    log.info("Done.")
    return {"records": len(data.get("data", []))}
