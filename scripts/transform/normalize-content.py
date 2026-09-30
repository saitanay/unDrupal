#!/usr/bin/env python3
"""
normalize-content.py — Normalize exported Drupal content to a standard JSON schema.

Drupal content can be exported via multiple methods (JSON:API, database SQL, Drush,
YAML config export), each producing different structures. This script normalizes
any of those formats into a consistent JSON schema suitable for import into a
target platform.

Usage:
    python normalize-content.py --input export.json --output normalized.json --format jsonapi
    python normalize-content.py --input rows.json --output normalized.json --format sql --schema schema.json
    python normalize-content.py --input content.yml --output normalized.json --format yaml --verbose
"""

from __future__ import annotations

import argparse
import csv
import io
import json
import re
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple, Union

try:
    import yaml as yaml_lib
except ImportError:
    yaml_lib = None  # type: ignore[assignment]


# Default content schema template
DEFAULT_SCHEMA: Dict[str, Any] = {
    "version": "1.0",
    "entity_type": "node",
    "fields": {
        "id": {"type": "string", "required": True},
        "uuid": {"type": "string", "required": False},
        "type": {"type": "string", "required": True},
        "title": {"type": "string", "required": True},
        "status": {"type": "boolean", "required": False, "default": True},
        "langcode": {"type": "string", "required": False, "default": "en"},
        "created": {"type": "datetime", "required": False},
        "changed": {"type": "datetime", "required": False},
        "author": {"type": "string", "required": False},
        "path": {"type": "string", "required": False},
        "body": {"type": "rich_text", "required": False},
        "summary": {"type": "string", "required": False},
        "fields": {"type": "object", "required": False},
    },
}


def load_schema(schema_path: Optional[str]) -> Dict[str, Any]:
    """Load a custom schema or return the default."""
    if not schema_path:
        return DEFAULT_SCHEMA

    path = Path(schema_path)
    if not path.exists():
        print(f"Error: schema file not found: {path}", file=sys.stderr)
        sys.exit(1)

    with open(path, "r", encoding="utf-8") as f:
        return json.load(f)


def parse_timestamp(value: Any) -> Optional[str]:
    """Convert various timestamp formats to ISO 8601."""
    if value is None:
        return None

    if isinstance(value, (int, float)):
        # Unix timestamp
        try:
            dt = datetime.fromtimestamp(value, tz=timezone.utc)
            return dt.isoformat()
        except (OSError, ValueError, OverflowError):
            return str(value)

    if isinstance(value, str):
        value = value.strip()
        if not value:
            return None
        # Already ISO format
        if re.match(r'^\d{4}-\d{2}-\d{2}T', value):
            return value
        # Unix timestamp as string
        if re.match(r'^\d{10,}$', value):
            try:
                dt = datetime.fromtimestamp(int(value), tz=timezone.utc)
                return dt.isoformat()
            except (OSError, ValueError, OverflowError):
                return value
        # MySQL datetime
        if re.match(r'^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}', value):
            return value.replace(" ", "T") + "+00:00"

    return str(value) if value else None


def normalize_boolean(value: Any) -> bool:
    """Normalize various boolean representations."""
    if isinstance(value, bool):
        return value
    if isinstance(value, (int, float)):
        return value != 0
    if isinstance(value, str):
        return value.lower() in ("1", "true", "yes", "on", "published")
    return bool(value)


def extract_text_value(value: Any) -> Optional[str]:
    """Extract text from Drupal field value structures."""
    if value is None:
        return None
    if isinstance(value, str):
        return value
    if isinstance(value, list):
        if len(value) == 0:
            return None
        first = value[0]
        if isinstance(first, dict):
            return first.get("value") or first.get("processed") or first.get("summary")
        return str(first)
    if isinstance(value, dict):
        return value.get("value") or value.get("processed")
    return str(value)


def extract_summary(value: Any) -> Optional[str]:
    """Extract summary from body field structures."""
    if isinstance(value, list) and len(value) > 0:
        first = value[0]
        if isinstance(first, dict):
            return first.get("summary")
    if isinstance(value, dict):
        return value.get("summary")
    return None


# --- Format-specific normalizers ---

def normalize_jsonapi(data: Any, schema: Dict[str, Any], verbose: bool = False) -> List[Dict[str, Any]]:
    """Normalize a JSON:API compound document."""
    results: List[Dict[str, Any]] = []

    items = data.get("data", [])
    if isinstance(items, dict):
        items = [items]

    # Build included lookup
    included: Dict[str, Dict[str, Any]] = {}
    for inc in data.get("included", []):
        if isinstance(inc, dict) and "id" in inc and "type" in inc:
            included[f"{inc['type']}:{inc['id']}"] = inc

    for item in items:
        if not isinstance(item, dict):
            continue

        attrs = item.get("attributes", {})
        rels = item.get("relationships", {})
        item_type = item.get("type", "")

        # Split JSON:API type "node--article" -> "article"
        bundle = item_type.split("--", 1)[1] if "--" in item_type else item_type

        normalized: Dict[str, Any] = {
            "id": str(item.get("id", "")),
            "uuid": str(item.get("id", "")),
            "type": bundle,
            "title": attrs.get("title", ""),
            "status": normalize_boolean(attrs.get("status", True)),
            "langcode": attrs.get("langcode", "en"),
            "created": parse_timestamp(attrs.get("created")),
            "changed": parse_timestamp(attrs.get("changed")),
        }

        # Path alias
        path_data = attrs.get("path", {})
        if isinstance(path_data, dict):
            normalized["path"] = path_data.get("alias", "")
        elif isinstance(path_data, str):
            normalized["path"] = path_data

        # Body / summary
        body_data = attrs.get("body", {})
        normalized["body"] = extract_text_value(body_data)
        normalized["summary"] = extract_summary(body_data)

        # Author from relationships
        author_rel = rels.get("uid", rels.get("revision_uid", {}))
        if isinstance(author_rel, dict):
            author_data = author_rel.get("data", {})
            if isinstance(author_data, dict):
                author_id = author_data.get("id", "")
                author_key = f"{author_data.get('type', 'user--user')}:{author_id}"
                author_inc = included.get(author_key, {})
                author_attrs = author_inc.get("attributes", {})
                normalized["author"] = author_attrs.get("display_name") or author_attrs.get("name") or author_id

        # Collect all other attributes as custom fields
        custom_fields: Dict[str, Any] = {}
        skip_attrs = {"title", "status", "langcode", "created", "changed", "path", "body",
                       "default_langcode", "revision_timestamp", "revision_log",
                       "revision_translation_affected", "content_translation_source",
                       "content_translation_outdated", "promote", "sticky"}
        for attr_name, attr_value in attrs.items():
            if attr_name in skip_attrs:
                continue
            if attr_name.startswith("field_") or attr_name not in skip_attrs:
                custom_fields[attr_name] = extract_text_value(attr_value) if _is_simple_field(attr_value) else attr_value

        # Collect non-structural relationships as references
        skip_rels = {"uid", "revision_uid", "node_type", "type"}
        for rel_name, rel_value in rels.items():
            if rel_name in skip_rels:
                continue
            if isinstance(rel_value, dict):
                rel_data = rel_value.get("data")
                if rel_data is not None:
                    custom_fields[rel_name] = rel_data

        if custom_fields:
            normalized["fields"] = custom_fields

        results.append(normalized)

    if verbose:
        print(f"[normalize] Processed {len(results)} items from JSON:API format", file=sys.stderr)

    return results


def _is_simple_field(value: Any) -> bool:
    """Check if a field value is a simple text-like structure."""
    if isinstance(value, (str, int, float, bool)):
        return True
    if isinstance(value, dict) and "value" in value and len(value) <= 3:
        return True
    if isinstance(value, list) and len(value) == 1:
        if isinstance(value[0], dict) and "value" in value[0]:
            return True
    return False


def normalize_sql(data: Any, schema: Dict[str, Any], verbose: bool = False) -> List[Dict[str, Any]]:
    """
    Normalize raw SQL row output.

    Expects a list of row objects with column names matching Drupal database columns.
    """
    results: List[Dict[str, Any]] = []

    if isinstance(data, dict):
        # Might be keyed by table name
        for key, rows in data.items():
            if isinstance(rows, list):
                results.extend(_normalize_sql_rows(rows))
        if not results and all(isinstance(v, (str, int, float, bool, type(None))) for v in data.values()):
            results = _normalize_sql_rows([data])
    elif isinstance(data, list):
        results = _normalize_sql_rows(data)

    if verbose:
        print(f"[normalize] Processed {len(results)} rows from SQL format", file=sys.stderr)

    return results


def _normalize_sql_rows(rows: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
    """Normalize a list of SQL row dicts."""
    results: List[Dict[str, Any]] = []

    for row in rows:
        if not isinstance(row, dict):
            continue

        normalized: Dict[str, Any] = {
            "id": str(row.get("nid", row.get("id", row.get("entity_id", "")))),
            "uuid": row.get("uuid", ""),
            "type": row.get("type", row.get("bundle", row.get("node_type", ""))),
            "title": row.get("title", ""),
            "status": normalize_boolean(row.get("status", 1)),
            "langcode": row.get("langcode", "en"),
            "created": parse_timestamp(row.get("created")),
            "changed": parse_timestamp(row.get("changed")),
        }

        # Author
        uid = row.get("uid", row.get("revision_uid"))
        if uid is not None:
            normalized["author"] = str(uid)

        # Path
        alias = row.get("alias", row.get("path_alias"))
        if alias:
            normalized["path"] = alias

        # Body
        body = row.get("body_value", row.get("body", ""))
        if body:
            normalized["body"] = body
        summary = row.get("body_summary", row.get("summary"))
        if summary:
            normalized["summary"] = summary

        # Custom fields (anything starting with field_)
        custom_fields: Dict[str, Any] = {}
        for col, val in row.items():
            if col.startswith("field_") and val is not None:
                # Strip _value suffix that Drupal DB adds
                clean_name = re.sub(r'_value$', '', col)
                custom_fields[clean_name] = val
            elif col not in {
                "nid", "id", "entity_id", "uuid", "type", "bundle", "node_type",
                "title", "status", "langcode", "created", "changed", "uid",
                "revision_uid", "alias", "path_alias", "body_value", "body",
                "body_summary", "summary", "vid", "revision_id", "delta",
                "deleted", "default_langcode",
            } and val is not None:
                custom_fields[col] = val

        if custom_fields:
            normalized["fields"] = custom_fields

        results.append(normalized)

    return results


def normalize_yaml(data: Any, schema: Dict[str, Any], verbose: bool = False) -> List[Dict[str, Any]]:
    """Normalize YAML content export format."""
    results: List[Dict[str, Any]] = []

    if isinstance(data, list):
        for item in data:
            if isinstance(item, dict):
                results.append(_normalize_yaml_item(item))
    elif isinstance(data, dict):
        # Single item or keyed collection
        if "uuid" in data or "nid" in data or "title" in data:
            results.append(_normalize_yaml_item(data))
        else:
            for key, item in data.items():
                if isinstance(item, dict):
                    results.append(_normalize_yaml_item(item))
                elif isinstance(item, list):
                    for sub in item:
                        if isinstance(sub, dict):
                            results.append(_normalize_yaml_item(sub))

    if verbose:
        print(f"[normalize] Processed {len(results)} items from YAML format", file=sys.stderr)

    return results


def _normalize_yaml_item(item: Dict[str, Any]) -> Dict[str, Any]:
    """Normalize a single YAML content item."""
    normalized: Dict[str, Any] = {
        "id": str(item.get("nid", item.get("id", item.get("uuid", "")))),
        "uuid": item.get("uuid", ""),
        "type": item.get("type", item.get("bundle", "")),
        "title": item.get("title", item.get("label", item.get("name", ""))),
        "status": normalize_boolean(item.get("status", True)),
        "langcode": item.get("langcode", item.get("language", "en")),
        "created": parse_timestamp(item.get("created")),
        "changed": parse_timestamp(item.get("changed", item.get("modified"))),
    }

    # Author
    author = item.get("uid", item.get("author"))
    if author is not None:
        if isinstance(author, dict):
            normalized["author"] = author.get("name", author.get("target_id", str(author)))
        else:
            normalized["author"] = str(author)

    # Path
    path = item.get("path", item.get("alias"))
    if isinstance(path, dict):
        normalized["path"] = path.get("alias", "")
    elif isinstance(path, str):
        normalized["path"] = path

    # Body
    body = item.get("body", item.get("field_body"))
    normalized["body"] = extract_text_value(body)
    normalized["summary"] = extract_summary(body)

    # Custom fields
    custom_fields: Dict[str, Any] = {}
    skip_keys = {
        "nid", "id", "uuid", "type", "bundle", "title", "label", "name",
        "status", "langcode", "language", "created", "changed", "modified",
        "uid", "author", "path", "alias", "body", "field_body",
        "vid", "revision_id", "default_langcode",
    }
    for key, val in item.items():
        if key not in skip_keys and val is not None:
            custom_fields[key] = val

    if custom_fields:
        normalized["fields"] = custom_fields

    return normalized


def normalize_drupal_export(data: Any, schema: Dict[str, Any], verbose: bool = False) -> List[Dict[str, Any]]:
    """
    Normalize Drupal drush content-export format.

    This is a catch-all for drush-generated exports that may combine
    entity data with field values in various structures.
    """
    results: List[Dict[str, Any]] = []

    if isinstance(data, list):
        for item in data:
            if isinstance(item, dict):
                # Detect format: JSON:API-like, SQL-like, or raw
                if "attributes" in item and "type" in item:
                    # JSON:API-like
                    results.extend(normalize_jsonapi({"data": [item]}, schema, verbose=False))
                elif "nid" in item or "entity_id" in item:
                    # SQL-like
                    results.extend(_normalize_sql_rows([item]))
                else:
                    results.append(_normalize_yaml_item(item))
    elif isinstance(data, dict):
        if "data" in data:
            return normalize_jsonapi(data, schema, verbose)
        for key, val in data.items():
            if isinstance(val, list):
                for item in val:
                    if isinstance(item, dict):
                        results.append(_normalize_yaml_item(item))
            elif isinstance(val, dict):
                results.append(_normalize_yaml_item(val))

    if verbose:
        print(f"[normalize] Processed {len(results)} items from drupal-export format", file=sys.stderr)

    return results


FORMAT_HANDLERS = {
    "jsonapi": normalize_jsonapi,
    "sql": normalize_sql,
    "yaml": normalize_yaml,
    "drupal-export": normalize_drupal_export,
}


def load_input(input_path: Path, fmt: str) -> Any:
    """Load input data from file based on format."""
    if fmt == "yaml":
        if yaml_lib is None:
            # Try JSON first
            try:
                with open(input_path, "r", encoding="utf-8") as f:
                    return json.load(f)
            except json.JSONDecodeError:
                print(
                    "Error: PyYAML is required to parse YAML files.\n"
                    "Install with: pip install pyyaml",
                    file=sys.stderr,
                )
                sys.exit(1)
        with open(input_path, "r", encoding="utf-8") as f:
            return yaml_lib.safe_load(f)

    with open(input_path, "r", encoding="utf-8") as f:
        return json.load(f)


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Normalize exported Drupal content to a standard JSON schema.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=(
            "Supported formats:\n"
            "  jsonapi        JSON:API compound document (data + included)\n"
            "  sql            Raw SQL row output as JSON array\n"
            "  yaml           YAML content export (requires PyYAML)\n"
            "  drupal-export  Generic drush export (auto-detects sub-format)\n"
            "\n"
            "Examples:\n"
            "  python normalize-content.py --input api.json --output out.json --format jsonapi\n"
            "  python normalize-content.py --input rows.json --output out.json --format sql\n"
            "  python normalize-content.py --input content.yml --output out.json --format yaml\n"
        ),
    )
    parser.add_argument(
        "--input", required=True,
        help="Path to exported content file (JSON or YAML)",
    )
    parser.add_argument(
        "--output", required=True,
        help="Path to write normalized JSON output",
    )
    parser.add_argument(
        "--format", required=True,
        choices=["jsonapi", "sql", "yaml", "drupal-export"],
        help="Input format type",
    )
    parser.add_argument(
        "--schema",
        help="Path to custom JSON schema template (optional)",
    )
    parser.add_argument(
        "--verbose", action="store_true",
        help="Print progress and statistics to stderr",
    )
    args = parser.parse_args()

    input_path = Path(args.input)
    if not input_path.exists():
        print(f"Error: input file not found: {input_path}", file=sys.stderr)
        sys.exit(1)

    schema = load_schema(args.schema)

    if args.verbose:
        print(f"[normalize] Reading {input_path} as {args.format}", file=sys.stderr)

    try:
        data = load_input(input_path, args.format)
    except json.JSONDecodeError as exc:
        print(f"Error: invalid JSON in {input_path}: {exc}", file=sys.stderr)
        sys.exit(1)
    except Exception as exc:
        print(f"Error: could not read {input_path}: {exc}", file=sys.stderr)
        sys.exit(1)

    handler = FORMAT_HANDLERS[args.format]
    normalized = handler(data, schema, verbose=args.verbose)

    # Remove None values for cleaner output
    cleaned = []
    for item in normalized:
        cleaned_item = {k: v for k, v in item.items() if v is not None}
        if "fields" in cleaned_item and not cleaned_item["fields"]:
            del cleaned_item["fields"]
        cleaned.append(cleaned_item)

    output = {
        "schema_version": schema.get("version", "1.0"),
        "entity_type": schema.get("entity_type", "node"),
        "count": len(cleaned),
        "items": cleaned,
    }

    if args.verbose:
        types: Dict[str, int] = {}
        for item in cleaned:
            t = item.get("type", "unknown")
            types[t] = types.get(t, 0) + 1
        print(f"[normalize] Output: {len(cleaned)} items", file=sys.stderr)
        for t, count in sorted(types.items()):
            print(f"[normalize]   {t}: {count}", file=sys.stderr)

    output_path = Path(args.output)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    with open(output_path, "w", encoding="utf-8") as f:
        json.dump(output, f, indent=2, ensure_ascii=False)

    if args.verbose:
        print(f"[normalize] Wrote {output_path}", file=sys.stderr)


if __name__ == "__main__":
    main()
