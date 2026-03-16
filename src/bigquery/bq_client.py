"""Minimal BigQuery proof-of-concept client for pipeline operations."""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
import uuid
from dataclasses import dataclass
from datetime import datetime, timezone
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


def resolve_config(tfvars_path: Path, project_id: str | None, dataset_id: str | None, table_id: str | None) -> BigQueryConfig:
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
        or os.getenv("BQ_TABLE_ID")
        or tfvars_values.get("bigquery_operations_table_id")
        or "pipeline_operations"
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


def _prepare_details_value(
    client: "bigquery.Client", config: BigQueryConfig, details_json: dict[str, Any]
) -> Any:
    """Match the inserted details value to the table's current schema type."""
    table = client.get_table(config.table_fqn)
    details_field = next((field for field in table.schema if field.name == "details_json"), None)
    if details_field is None:
        raise RuntimeError(f"Column details_json not found in {config.table_fqn}.")

    # BigQuery JSON columns expect a JSON-formatted string in streaming inserts.
    if details_field.field_type == "JSON":
        return json.dumps(details_json)

    # Backward compatibility for older schemas that may have used RECORD.
    if details_field.field_type == "RECORD":
        return details_json

    # String columns can still hold structured payloads as serialized JSON.
    if details_field.field_type == "STRING":
        return json.dumps(details_json)

    raise RuntimeError(
        f"Unsupported details_json field type {details_field.field_type!r} in {config.table_fqn}."
    )


def insert_demo_operation(
    config: BigQueryConfig,
    operation_type: str,
    status: str,
    source_system: str | None,
    details_json: dict[str, Any],
) -> dict[str, Any]:
    client = _create_client(config.project_id)
    details_value = _prepare_details_value(client, config, details_json)
    now_utc = datetime.now(timezone.utc).isoformat()
    row = {
        "operation_id": str(uuid.uuid4()),
        "operation_type": operation_type,
        "status": status,
        "source_system": source_system,
        "details_json": details_value,
        "created_at": now_utc,
        "updated_at": now_utc,
    }

    errors = client.insert_rows_json(config.table_fqn, [row])
    if errors:
        raise RuntimeError(f"Insert failed: {json.dumps(errors)}")
    return row


def query_recent_operations(config: BigQueryConfig, limit: int) -> list[dict[str, Any]]:
    client = _create_client(config.project_id)
    query = f"""
        SELECT
            operation_id,
            operation_type,
            status,
            source_system,
            details_json,
            created_at,
            updated_at
        FROM `{config.table_fqn}`
        ORDER BY created_at DESC
        LIMIT @row_limit
    """
    job_config = bigquery.QueryJobConfig(
        query_parameters=[bigquery.ScalarQueryParameter("row_limit", "INT64", limit)]
    )
    rows = client.query(query, job_config=job_config).result()
    return [dict(row.items()) for row in rows]


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
        description="Minimal BigQuery POC utility for pipeline_operations table."
    )
    subparsers = parser.add_subparsers(dest="command", required=True)

    show_config = subparsers.add_parser("show-config", help="Print resolved BigQuery config.")
    _add_common_args(show_config)

    insert_demo = subparsers.add_parser("insert-demo", help="Insert one demo operation row.")
    _add_common_args(insert_demo)
    insert_demo.add_argument("--operation-type", default="poc_insert")
    insert_demo.add_argument("--status", default="PENDING")
    insert_demo.add_argument("--source-system", default="manual-test")
    insert_demo.add_argument(
        "--details-json",
        default='{"note":"poc row inserted by bq_client.py"}',
        help="JSON object string for details_json column.",
    )

    query_recent = subparsers.add_parser(
        "query-recent", help="Query most recent operation rows."
    )
    _add_common_args(query_recent)
    query_recent.add_argument("--limit", type=int, default=10)

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

    if args.command == "insert-demo":
        try:
            details_json = json.loads(args.details_json)
        except json.JSONDecodeError as exc:
            raise ValueError(f"--details-json must be valid JSON: {exc}") from exc
        row = insert_demo_operation(
            config=config,
            operation_type=args.operation_type,
            status=args.status,
            source_system=args.source_system,
            details_json=details_json,
        )
        print(json.dumps(row, indent=2, default=str))
        return 0

    if args.command == "query-recent":
        rows = query_recent_operations(config=config, limit=args.limit)
        print(json.dumps(rows, indent=2, default=str))
        return 0

    parser.print_help()
    return 1


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as exc:  # pylint: disable=broad-except
        print(f"ERROR: {exc}", file=sys.stderr)
        raise SystemExit(1) from exc
