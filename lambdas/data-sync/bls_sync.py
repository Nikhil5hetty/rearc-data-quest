"""
BLS Dataset Sync — Part 1
Fetches every file from https://download.bls.gov/pub/time.series/pr/
and syncs them to an S3 bucket (production) or a local directory (dev/test).

BLS policy compliance: a User-Agent header with contact info is required.
See https://www.bls.gov/bls/pss.htm
"""

import hashlib
import logging
import os
import re
from abc import ABC, abstractmethod
from pathlib import Path

import requests

BLS_BASE_URL = os.environ.get("BLS_BASE_URL", "https://download.bls.gov/pub/time.series/pr/")
USER_AGENT = os.environ.get(
    "BLS_USER_AGENT",
    "rearc-data-quest/1.0 (data-engineering-assessment; contact: your@email.com)",
)

log = logging.getLogger(__name__)


# ---------------------------------------------------------------------------
# Storage abstraction
# ---------------------------------------------------------------------------

class StorageBackend(ABC):
    @abstractmethod
    def list_files(self) -> dict[str, str]: ...
    @abstractmethod
    def write_file(self, filename: str, content: bytes, content_type: str) -> None: ...
    @abstractmethod
    def delete_file(self, filename: str) -> None: ...
    @abstractmethod
    def describe(self) -> str: ...


class LocalStorage(StorageBackend):
    def __init__(self, directory: str) -> None:
        self.root = Path(directory)
        self.root.mkdir(parents=True, exist_ok=True)

    def list_files(self) -> dict[str, str]:
        result: dict[str, str] = {}
        for path in self.root.iterdir():
            if path.is_file():
                result[path.name] = md5_of_bytes(path.read_bytes())
        log.info("Found %d file(s) in %s", len(result), self.root)
        return result

    def write_file(self, filename: str, content: bytes, content_type: str) -> None:
        (self.root / filename).write_bytes(content)
        log.info("Written %d bytes → %s", len(content), self.root / filename)

    def delete_file(self, filename: str) -> None:
        (self.root / filename).unlink(missing_ok=True)
        log.info("Deleted %s", self.root / filename)

    def describe(self) -> str:
        return str(self.root.resolve())


class S3Storage(StorageBackend):
    def __init__(self, bucket: str, prefix: str, region: str) -> None:
        import boto3
        from botocore.exceptions import ClientError

        self.bucket = bucket
        self.prefix = prefix
        self.region = region
        self._client = boto3.client("s3", region_name=region)
        self._ClientError = ClientError
        self._ensure_bucket_exists()

    def _ensure_bucket_exists(self) -> None:
        try:
            self._client.head_bucket(Bucket=self.bucket)
            log.info("Bucket '%s' exists.", self.bucket)
        except self._ClientError as exc:
            code = exc.response["Error"]["Code"]
            if code in ("404", "NoSuchBucket"):
                log.info("Creating bucket '%s' in %s.", self.bucket, self.region)
                if self.region == "us-east-1":
                    self._client.create_bucket(Bucket=self.bucket)
                else:
                    self._client.create_bucket(
                        Bucket=self.bucket,
                        CreateBucketConfiguration={"LocationConstraint": self.region},
                    )
            else:
                raise

    def list_files(self) -> dict[str, str]:
        paginator = self._client.get_paginator("list_objects_v2")
        result: dict[str, str] = {}
        for page in paginator.paginate(Bucket=self.bucket, Prefix=self.prefix):
            for obj in page.get("Contents", []):
                key = obj["Key"][len(self.prefix):]
                if key:
                    result[key] = obj["ETag"].strip('"')
        log.info("Found %d object(s) in s3://%s/%s", len(result), self.bucket, self.prefix)
        return result

    def write_file(self, filename: str, content: bytes, content_type: str) -> None:
        key = self.prefix + filename
        self._client.put_object(Bucket=self.bucket, Key=key, Body=content, ContentType=content_type)
        log.info("Uploaded %d bytes → s3://%s/%s", len(content), self.bucket, key)

    def delete_file(self, filename: str) -> None:
        key = self.prefix + filename
        self._client.delete_object(Bucket=self.bucket, Key=key)
        log.info("Deleted s3://%s/%s", self.bucket, key)

    def describe(self) -> str:
        return f"s3://{self.bucket}/{self.prefix}"


# ---------------------------------------------------------------------------
# BLS helpers
# ---------------------------------------------------------------------------

def get_http_session() -> requests.Session:
    session = requests.Session()
    session.headers.update({"User-Agent": USER_AGENT})
    return session


def list_bls_files(session: requests.Session) -> dict[str, str]:
    log.info("Fetching BLS directory listing from %s", BLS_BASE_URL)
    response = session.get(BLS_BASE_URL, timeout=30)
    response.raise_for_status()

    pattern = re.compile(
        r"(\d{1,2}/\d{1,2}/\d{4}\s+\d{1,2}:\d{2}\s+[AP]M)"
        r"\s+\d+"
        r'\s+<A HREF="[^"]*">([^<]+)</A>',
        re.IGNORECASE,
    )
    files: dict[str, str] = {}
    for match in pattern.finditer(response.text):
        last_modified, filename = match.group(1), match.group(2).strip()
        files[filename] = last_modified
    log.info("Found %d file(s) in BLS directory", len(files))
    return files


def md5_of_bytes(data: bytes) -> str:
    return hashlib.md5(data).hexdigest()


# ---------------------------------------------------------------------------
# Core sync logic
# ---------------------------------------------------------------------------

def sync(storage: StorageBackend, dry_run: bool = False) -> dict:
    log.info("Syncing BLS → %s%s", storage.describe(), "  [DRY RUN]" if dry_run else "")
    session = get_http_session()
    bls_files = list_bls_files(session)
    stored_files = storage.list_files()

    to_add = set(bls_files) - set(stored_files)
    to_check = set(bls_files) & set(stored_files)
    to_delete = set(stored_files) - set(bls_files)
    stats = {"uploaded": 0, "skipped": 0, "deleted": 0}

    for filename in sorted(to_add):
        log.info("[NEW] %s", filename)
        if not dry_run:
            resp = session.get(BLS_BASE_URL + filename, timeout=120)
            resp.raise_for_status()
            storage.write_file(filename, resp.content, resp.headers.get("Content-Type", "application/octet-stream"))
        stats["uploaded"] += 1

    for filename in sorted(to_check):
        stored_md5 = stored_files[filename]
        resp = session.get(BLS_BASE_URL + filename, timeout=120)
        resp.raise_for_status()
        current_md5 = md5_of_bytes(resp.content)
        if current_md5 == stored_md5:
            log.info("[SKIP] %s – unchanged", filename)
            stats["skipped"] += 1
        else:
            log.info("[UPDATE] %s – changed", filename)
            if not dry_run:
                storage.write_file(filename, resp.content, resp.headers.get("Content-Type", "application/octet-stream"))
            stats["uploaded"] += 1

    for filename in sorted(to_delete):
        log.info("[DELETE] %s", filename)
        if not dry_run:
            storage.delete_file(filename)
        stats["deleted"] += 1

    log.info("Done. uploaded=%d skipped=%d deleted=%d", stats["uploaded"], stats["skipped"], stats["deleted"])
    return stats
