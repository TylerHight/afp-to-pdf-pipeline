"""BigQuery client helpers for VM work locking and lease coordination."""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
import time
import uuid
from dataclasses import dataclass
from pathlib import Path
from typing import Any

try:
    from google.cloud import bigquery
except ImportError:  # pragma: no cover - dependency may not be installed in all dev environments
    bigquery = None


@dataclass(frozen=True)
class BigQueryConfig:
    project_id: str
    dataset_id: str
    table_id: str

    @property
    def table_fqn(self) -> str:
        return f"{self.project_id}.{self.dataset_id}.{self.table_id}"


_TFVAR_ASSIGNMENT = re.compile(r"^([A-Za-z0-9_]+)\s*=\s*(.+)$")
_RETRYABLE_CLAIM_ERRORS = (
    "could not serialize access",
    "concurrent update",
    "aborted due to concurrent update",
)


def _read_tfvars(tfvars_path: Path) -> dict[str, Any]:
    if not tfvars_path.exists():
        return {}

    values: dict[str, Any] = {}
    for raw_line in tfvars_path.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue

        if "#" in line:
            line = line.split("#", 1)[0].strip()

        match = _TFVAR_ASSIGNMENT.match(line)
        if not match:
            continue

        key, raw_value = match.groups()
        value = raw_value.strip().rstrip(",")

        if value.startswith('"') and value.endswith('"'):
            values[key] = value[1:-1].replace('\\"', '"')
            continue

        if value.lower() in {"true", "false"}:
            values[key] = value.lower() == "true"
            continue

        if re.fullmatch(r"-?\d+", value):
            values[key] = int(value)
            continue

        values[key] = value

    return values


def _default_tfvars_path() -> Path:
    return Path(__file__).resolve().parents[2] / "infrastructure" / "terraform" / "terraform.tfvars"


def resolve_config(
    tfvars_path: Path,
    project_id: str | None,
    dataset_id: str | None,
    table_id: str | None,
) -> BigQueryConfig:
    tfvars_values = _read_tfvars(tfvars_path)

    resolved_project = (
        project_id
        or os.getenv("BQ_PROJECT_ID")
        or os.getenv("GOOGLE_CLOUD_PROJECT")
        or tfvars_values.get("project_id")
    )
    resolved_dataset = (
        dataset_id
        or os.getenv("BQ_DATASET_ID")
        or tfvars_values.get("bigquery_dataset_id")
        or "afp_pdf_poc"
    )
    resolved_table = (
        table_id
        or os.getenv("BQ_LOCK_TABLE_ID")
        or os.getenv("BQ_TABLE_ID")
        or tfvars_values.get("bigquery_lock_table_id")
        or "work_locks"
    )

    if not resolved_project:
        raise ValueError(
            "Missing GCP project_id. Set --project-id, BQ_PROJECT_ID, GOOGLE_CLOUD_PROJECT, "
            "or define project_id in terraform.tfvars."
        )

    return BigQueryConfig(
        project_id=str(resolved_project),
        dataset_id=str(resolved_dataset),
        table_id=str(resolved_table),
    )


def _require_bigquery_dependency() -> None:
    if bigquery is None:
        raise RuntimeError(
            "google-cloud-bigquery is not installed. Run: pip install google-cloud-bigquery"
        )


def _create_client(project_id: str) -> "bigquery.Client":
    _require_bigquery_dependency()
    return bigquery.Client(project=project_id)


def _parse_json_arg(raw_json: str) -> dict[str, Any]:
    try:
        parsed = json.loads(raw_json)
    except json.JSONDecodeError as exc:
        raise ValueError(f"Expected valid JSON object: {exc}") from exc

    if not isinstance(parsed, dict):
        raise ValueError("Expected a JSON object.")
    return parsed


def _row_to_dict(row: Any) -> dict[str, Any]:
    return dict(row.items())


def _fetch_lock_row(client: "bigquery.Client", config: BigQueryConfig, lock_id: str) -> dict[str, Any] | None:
    query = f"""
        SELECT *
        FROM `{config.table_fqn}`
        WHERE lock_id = @lock_id
        LIMIT 1
    """
    job_config = bigquery.QueryJobConfig(
        query_parameters=[bigquery.ScalarQueryParameter("lock_id", "STRING", lock_id)]
    )
    rows = list(client.query(query, job_config=job_config).result())
    return _row_to_dict(rows[0]) if rows else None


def create_lock(
    config: BigQueryConfig,
    *,
    work_type: str,
    shard_key: str,
    billing_cycle_date: str | None,
    ban_range_start: str | None,
    ban_range_end: str | None,
    ban_count: int | None,
    source_uri: str | None,
    destination_prefix: str | None,
    priority: int,
    max_attempts: int,
    metadata_json: dict[str, Any],
    lock_id: str | None = None,
) -> dict[str, Any]:
    client = _create_client(config.project_id)
    now_utc = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
    row = {
        "lock_id": lock_id or str(uuid.uuid4()),
        "work_type": work_type,
        "shard_key": shard_key,
        "billing_cycle_date": billing_cycle_date,
        "ban_range_start": ban_range_start,
        "ban_range_end": ban_range_end,
        "ban_count": ban_count,
        "source_uri": source_uri,
        "destination_prefix": destination_prefix,
        "status": "PENDING",
        "priority": priority,
        "attempt_count": 0,
        "max_attempts": max_attempts,
        "lease_owner": None,
        "lease_token": None,
        "lease_expires_at": None,
        "claimed_at": None,
        "last_heartbeat_at": None,
        "completed_at": None,
        "last_error": None,
        "metadata_json": json.dumps(metadata_json),
        "created_at": now_utc,
        "updated_at": now_utc,
    }

    errors = client.insert_rows_json(config.table_fqn, [row])
    if errors:
        raise RuntimeError(f"Insert failed: {json.dumps(errors)}")
    return row


def list_locks(config: BigQueryConfig, limit: int, status: str | None) -> list[dict[str, Any]]:
    client = _create_client(config.project_id)
    status_filter = "AND status = @status" if status else ""
    query = f"""
        SELECT *
        FROM `{config.table_fqn}`
        WHERE 1 = 1
        {status_filter}
        ORDER BY priority DESC, updated_at ASC, created_at ASC
        LIMIT @row_limit
    """
    parameters = [bigquery.ScalarQueryParameter("row_limit", "INT64", limit)]
    if status:
        parameters.append(bigquery.ScalarQueryParameter("status", "STRING", status))
    job_config = bigquery.QueryJobConfig(query_parameters=parameters)
    rows = client.query(query, job_config=job_config).result()
    return [_row_to_dict(row) for row in rows]


def claim_next_lock(
    config: BigQueryConfig,
    *,
    lease_owner: str,
    lease_seconds: int,
    work_type: str | None,
    max_retries: int,
) -> dict[str, Any] | None:
    client = _create_client(config.project_id)
    work_type_filter = "AND work_type = @work_type" if work_type else ""
    parameters_base = [
        bigquery.ScalarQueryParameter("lease_owner", "STRING", lease_owner),
        bigquery.ScalarQueryParameter("lease_seconds", "INT64", lease_seconds),
    ]
    if work_type:
        parameters_base.append(bigquery.ScalarQueryParameter("work_type", "STRING", work_type))

    for attempt in range(1, max_retries + 1):
        lease_token = str(uuid.uuid4())
        parameters = parameters_base + [
            bigquery.ScalarQueryParameter("lease_token", "STRING", lease_token)
        ]
        query = f"""
            DECLARE chosen_lock_id STRING;

            SET chosen_lock_id = (
              SELECT lock_id
              FROM `{config.table_fqn}`
              WHERE attempt_count < max_attempts
                AND (
                  status = 'PENDING'
                  OR (status = 'LEASED' AND lease_expires_at < CURRENT_TIMESTAMP())
                  OR (status = 'FAILED' AND lease_expires_at IS NULL)
                )
                {work_type_filter}
              ORDER BY priority DESC, updated_at ASC, created_at ASC
              LIMIT 1
            );

            UPDATE `{config.table_fqn}`
            SET
              status = 'LEASED',
              lease_owner = @lease_owner,
              lease_token = @lease_token,
              lease_expires_at = TIMESTAMP_ADD(CURRENT_TIMESTAMP(), INTERVAL @lease_seconds SECOND),
              claimed_at = IFNULL(claimed_at, CURRENT_TIMESTAMP()),
              last_heartbeat_at = CURRENT_TIMESTAMP(),
              updated_at = CURRENT_TIMESTAMP(),
              attempt_count = attempt_count + 1,
              last_error = NULL
            WHERE lock_id = chosen_lock_id
              AND chosen_lock_id IS NOT NULL
              AND attempt_count < max_attempts
              AND (
                status = 'PENDING'
                OR (status = 'LEASED' AND lease_expires_at < CURRENT_TIMESTAMP())
                OR (status = 'FAILED' AND lease_expires_at IS NULL)
              );

            SELECT *
            FROM `{config.table_fqn}`
            WHERE lease_token = @lease_token
            LIMIT 1;
        """

        try:
            job_config = bigquery.QueryJobConfig(query_parameters=parameters)
            rows = list(client.query(query, job_config=job_config).result())
        except Exception as exc:  # pylint: disable=broad-except
            message = str(exc).lower()
            if attempt < max_retries and any(text in message for text in _RETRYABLE_CLAIM_ERRORS):
                time.sleep(min(0.5 * attempt, 2.0))
                continue
            raise

        if rows:
            return _row_to_dict(rows[0])

    return None


def _update_lock_state(
    config: BigQueryConfig,
    *,
    lock_id: str,
    lease_token: str,
    set_clause: str,
    query_parameters: list[Any],
) -> dict[str, Any]:
    client = _create_client(config.project_id)
    parameters = [
        bigquery.ScalarQueryParameter("lock_id", "STRING", lock_id),
        bigquery.ScalarQueryParameter("lease_token", "STRING", lease_token),
    ] + query_parameters

    query = f"""
        UPDATE `{config.table_fqn}`
        SET {set_clause}
        WHERE lock_id = @lock_id
          AND lease_token = @lease_token
          AND status = 'LEASED'
    """
    job_config = bigquery.QueryJobConfig(query_parameters=parameters)
    job = client.query(query, job_config=job_config)
    job.result()

    if (job.num_dml_affected_rows or 0) != 1:
        raise RuntimeError(
            "Lock update rejected. The lock may be missing, already completed, or owned by another VM."
        )

    row = _fetch_lock_row(client, config, lock_id)
    if row is None:
        raise RuntimeError(f"Lock {lock_id} was updated but could not be reloaded.")
    return row


def heartbeat_lock(
    config: BigQueryConfig,
    *,
    lock_id: str,
    lease_token: str,
    lease_seconds: int,
) -> dict[str, Any]:
    return _update_lock_state(
        config,
        lock_id=lock_id,
        lease_token=lease_token,
        set_clause="""
          lease_expires_at = TIMESTAMP_ADD(CURRENT_TIMESTAMP(), INTERVAL @lease_seconds SECOND),
          last_heartbeat_at = CURRENT_TIMESTAMP(),
          updated_at = CURRENT_TIMESTAMP()
        """,
        query_parameters=[
            bigquery.ScalarQueryParameter("lease_seconds", "INT64", lease_seconds)
        ],
    )


def complete_lock(config: BigQueryConfig, *, lock_id: str, lease_token: str) -> dict[str, Any]:
    return _update_lock_state(
        config,
        lock_id=lock_id,
        lease_token=lease_token,
        set_clause="""
          status = 'DONE',
          completed_at = CURRENT_TIMESTAMP(),
          lease_owner = NULL,
          lease_token = NULL,
          lease_expires_at = NULL,
          updated_at = CURRENT_TIMESTAMP()
        """,
        query_parameters=[],
    )


def fail_lock(
    config: BigQueryConfig,
    *,
    lock_id: str,
    lease_token: str,
    error_message: str,
) -> dict[str, Any]:
    return _update_lock_state(
        config,
        lock_id=lock_id,
        lease_token=lease_token,
        set_clause="""
          status = 'FAILED',
          last_error = @error_message,
          lease_owner = NULL,
          lease_token = NULL,
          lease_expires_at = NULL,
          updated_at = CURRENT_TIMESTAMP()
        """,
        query_parameters=[
            bigquery.ScalarQueryParameter("error_message", "STRING", error_message)
        ],
    )


def _add_common_args(parser: argparse.ArgumentParser) -> None:
    parser.add_argument("--project-id", help="GCP project ID (overrides terraform.tfvars).")
    parser.add_argument("--dataset-id", help="BigQuery dataset ID (overrides terraform.tfvars).")
    parser.add_argument("--table-id", help="BigQuery table ID (overrides terraform.tfvars).")
    parser.add_argument(
        "--tfvars-path",
        default=str(_default_tfvars_path()),
        help="Path to terraform.tfvars for default values.",
    )


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="BigQuery lock-table utility for AFP-to-PDF VM work leasing."
    )
    subparsers = parser.add_subparsers(dest="command", required=True)

    show_config = subparsers.add_parser("show-config", help="Print resolved BigQuery config.")
    _add_common_args(show_config)

    create_lock_parser = subparsers.add_parser("create-lock", help="Insert one pending lock row.")
    _add_common_args(create_lock_parser)
    create_lock_parser.add_argument("--lock-id", help="Optional explicit lock ID.")
    create_lock_parser.add_argument("--work-type", default="ban_day_batch")
    create_lock_parser.add_argument("--shard-key", required=True)
    create_lock_parser.add_argument("--billing-cycle-date")
    create_lock_parser.add_argument("--ban-range-start")
    create_lock_parser.add_argument("--ban-range-end")
    create_lock_parser.add_argument("--ban-count", type=int)
    create_lock_parser.add_argument("--source-uri")
    create_lock_parser.add_argument("--destination-prefix")
    create_lock_parser.add_argument("--priority", type=int, default=100)
    create_lock_parser.add_argument("--max-attempts", type=int, default=3)
    create_lock_parser.add_argument(
        "--metadata-json",
        default="{}",
        help="JSON object with workload details such as tar members or invoice month.",
    )

    list_locks_parser = subparsers.add_parser("list-locks", help="List lock rows.")
    _add_common_args(list_locks_parser)
    list_locks_parser.add_argument("--limit", type=int, default=25)
    list_locks_parser.add_argument("--status", help="Optional status filter (PENDING, LEASED, DONE, FAILED).")

    claim_next_parser = subparsers.add_parser("claim-next", help="Lease the next available work item.")
    _add_common_args(claim_next_parser)
    claim_next_parser.add_argument("--lease-owner", required=True, help="Stable VM identifier, such as hostname.")
    claim_next_parser.add_argument("--lease-seconds", type=int, default=900)
    claim_next_parser.add_argument("--work-type", help="Optional work type filter.")
    claim_next_parser.add_argument("--max-retries", type=int, default=5)

    heartbeat_parser = subparsers.add_parser("heartbeat", help="Extend a currently held lease.")
    _add_common_args(heartbeat_parser)
    heartbeat_parser.add_argument("--lock-id", required=True)
    heartbeat_parser.add_argument("--lease-token", required=True)
    heartbeat_parser.add_argument("--lease-seconds", type=int, default=900)

    complete_parser = subparsers.add_parser("complete", help="Mark a leased lock row done.")
    _add_common_args(complete_parser)
    complete_parser.add_argument("--lock-id", required=True)
    complete_parser.add_argument("--lease-token", required=True)

    fail_parser = subparsers.add_parser("fail", help="Mark a leased lock row failed.")
    _add_common_args(fail_parser)
    fail_parser.add_argument("--lock-id", required=True)
    fail_parser.add_argument("--lease-token", required=True)
    fail_parser.add_argument("--error-message", required=True)

    return parser


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)

    config = resolve_config(
        tfvars_path=Path(args.tfvars_path),
        project_id=args.project_id,
        dataset_id=args.dataset_id,
        table_id=args.table_id,
    )

    if args.command == "show-config":
        print(json.dumps({"table_fqn": config.table_fqn}, indent=2))
        return 0

    if args.command == "create-lock":
        row = create_lock(
            config=config,
            lock_id=args.lock_id,
            work_type=args.work_type,
            shard_key=args.shard_key,
            billing_cycle_date=args.billing_cycle_date,
            ban_range_start=args.ban_range_start,
            ban_range_end=args.ban_range_end,
            ban_count=args.ban_count,
            source_uri=args.source_uri,
            destination_prefix=args.destination_prefix,
            priority=args.priority,
            max_attempts=args.max_attempts,
            metadata_json=_parse_json_arg(args.metadata_json),
        )
        print(json.dumps(row, indent=2, default=str))
        return 0

    if args.command == "list-locks":
        rows = list_locks(config=config, limit=args.limit, status=args.status)
        print(json.dumps(rows, indent=2, default=str))
        return 0

    if args.command == "claim-next":
        row = claim_next_lock(
            config=config,
            lease_owner=args.lease_owner,
            lease_seconds=args.lease_seconds,
            work_type=args.work_type,
            max_retries=args.max_retries,
        )
        print(json.dumps(row, indent=2, default=str))
        return 0

    if args.command == "heartbeat":
        row = heartbeat_lock(
            config=config,
            lock_id=args.lock_id,
            lease_token=args.lease_token,
            lease_seconds=args.lease_seconds,
        )
        print(json.dumps(row, indent=2, default=str))
        return 0

    if args.command == "complete":
        row = complete_lock(
            config=config,
            lock_id=args.lock_id,
            lease_token=args.lease_token,
        )
        print(json.dumps(row, indent=2, default=str))
        return 0

    if args.command == "fail":
        row = fail_lock(
            config=config,
            lock_id=args.lock_id,
            lease_token=args.lease_token,
            error_message=args.error_message,
        )
        print(json.dumps(row, indent=2, default=str))
        return 0

    parser.print_help()
    return 1


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as exc:  # pylint: disable=broad-except
        print(f"ERROR: {exc}", file=sys.stderr)
        raise SystemExit(1) from exc
