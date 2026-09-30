#!/usr/bin/env python3
"""
validate-export.py — Validate a Drupal content export against the content model schema.

Reads a JSON export file and the content-model-schema.json definition, then
runs structural and data-quality checks: required fields present, field types
match expectations, entity references resolve, cardinality respected, and
values are non-empty where required. Produces a validation report in JSON or
human-readable format.

Input:  JSON export file + content-model-schema.json
Output: Validation report (JSON or text).

Usage:
    python validate-export.py --export export.json --schema content-model-schema.json
    python validate-export.py --export export.json --schema content-model-schema.json --format text --strict
    python validate-export.py --export export.json --schema content-model-schema.json --sample 50 --output report.json
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from collections import Counter, defaultdict
from datetime import datetime
from pathlib import Path
from typing import Any, Dict, List, Optional, Set, Tuple


# ---------------------------------------------------------------------------
# Severity levels
# ---------------------------------------------------------------------------

SEVERITY_ERROR = "error"
SEVERITY_WARNING = "warning"
SEVERITY_INFO = "info"


# ---------------------------------------------------------------------------
# Data classes for findings
# ---------------------------------------------------------------------------

class ValidationFinding:
    """A single validation finding."""

    def __init__(
        self,
        severity: str,
        category: str,
        message: str,
        entity_type: str = "",
        bundle: str = "",
        entity_id: str = "",
        field: str = "",
        details: Optional[Dict[str, Any]] = None,
    ):
        self.severity = severity
        self.category = category
        self.message = message
        self.entity_type = entity_type
        self.bundle = bundle
        self.entity_id = entity_id
        self.field = field
        self.details = details or {}

    def to_dict(self) -> Dict[str, Any]:
        result: Dict[str, Any] = {
            "severity": self.severity,
            "category": self.category,
            "message": self.message,
        }
        if self.entity_type:
            result["entity_type"] = self.entity_type
        if self.bundle:
            result["bundle"] = self.bundle
        if self.entity_id:
            result["entity_id"] = self.entity_id
        if self.field:
            result["field"] = self.field
        if self.details:
            result["details"] = self.details
        return result


class ValidationReport:
    """Collects findings and produces a summary report."""

    def __init__(self):
        self.findings: List[ValidationFinding] = []
        self.entity_counts: Dict[str, Dict[str, int]] = defaultdict(Counter)
        self.field_type_counts: Counter = Counter()
        self.started_at: str = datetime.utcnow().isoformat() + "Z"
        self.finished_at: Optional[str] = None

    def add(self, finding: ValidationFinding) -> None:
        self.findings.append(finding)

    def error(self, category: str, message: str, **kwargs: Any) -> None:
        self.add(ValidationFinding(SEVERITY_ERROR, category, message, **kwargs))

    def warning(self, category: str, message: str, **kwargs: Any) -> None:
        self.add(ValidationFinding(SEVERITY_WARNING, category, message, **kwargs))

    def info(self, category: str, message: str, **kwargs: Any) -> None:
        self.add(ValidationFinding(SEVERITY_INFO, category, message, **kwargs))

    @property
    def error_count(self) -> int:
        return sum(1 for f in self.findings if f.severity == SEVERITY_ERROR)

    @property
    def warning_count(self) -> int:
        return sum(1 for f in self.findings if f.severity == SEVERITY_WARNING)

    @property
    def info_count(self) -> int:
        return sum(1 for f in self.findings if f.severity == SEVERITY_INFO)

    def finalize(self) -> None:
        self.finished_at = datetime.utcnow().isoformat() + "Z"

    def to_dict(self) -> Dict[str, Any]:
        return {
            "validation_report": {
                "started_at": self.started_at,
                "finished_at": self.finished_at,
                "summary": {
                    "total_findings": len(self.findings),
                    "errors": self.error_count,
                    "warnings": self.warning_count,
                    "info": self.info_count,
                    "passed": self.error_count == 0,
                },
                "entity_counts": {
                    etype: dict(bundles)
                    for etype, bundles in self.entity_counts.items()
                },
                "findings": [f.to_dict() for f in self.findings],
            }
        }

    def to_text(self) -> str:
        lines: List[str] = []
        lines.append("=" * 72)
        lines.append("DRUPAL EXPORT VALIDATION REPORT")
        lines.append("=" * 72)
        lines.append(f"Started:  {self.started_at}")
        lines.append(f"Finished: {self.finished_at}")
        lines.append("")

        # Summary
        passed = "PASSED" if self.error_count == 0 else "FAILED"
        lines.append(f"Result: {passed}")
        lines.append(f"  Errors:   {self.error_count}")
        lines.append(f"  Warnings: {self.warning_count}")
        lines.append(f"  Info:     {self.info_count}")
        lines.append("")

        # Entity counts
        if self.entity_counts:
            lines.append("-" * 40)
            lines.append("Entity Counts")
            lines.append("-" * 40)
            for etype, bundles in sorted(self.entity_counts.items()):
                total = sum(bundles.values())
                lines.append(f"  {etype}: {total}")
                for bundle, count in sorted(bundles.items()):
                    lines.append(f"    - {bundle}: {count}")
            lines.append("")

        # Findings grouped by severity
        for severity in [SEVERITY_ERROR, SEVERITY_WARNING, SEVERITY_INFO]:
            group = [f for f in self.findings if f.severity == severity]
            if not group:
                continue
            lines.append("-" * 40)
            lines.append(f"{severity.upper()}S ({len(group)})")
            lines.append("-" * 40)
            for f in group:
                loc_parts = [p for p in [f.entity_type, f.bundle, f.entity_id, f.field] if p]
                loc = " > ".join(loc_parts) if loc_parts else ""
                prefix = f"  [{f.category}]"
                if loc:
                    prefix += f" ({loc})"
                lines.append(f"{prefix}: {f.message}")
            lines.append("")

        return "\n".join(lines)


# ---------------------------------------------------------------------------
# Schema loader
# ---------------------------------------------------------------------------

def load_schema(schema_path: Path) -> Dict[str, Any]:
    """Load and validate the content model schema file."""
    with open(schema_path, "r", encoding="utf-8") as f:
        schema = json.load(f)

    if "entity_types" not in schema:
        raise ValueError(
            f"Schema file {schema_path} missing 'entity_types' key. "
            "Expected a content-model-schema.json export."
        )
    return schema


def load_export(export_path: Path) -> Dict[str, Any]:
    """Load the content export JSON file."""
    with open(export_path, "r", encoding="utf-8") as f:
        data = json.load(f)
    return data


# ---------------------------------------------------------------------------
# Build lookup structures from schema
# ---------------------------------------------------------------------------

def build_field_map(schema: Dict[str, Any]) -> Dict[str, Dict[str, Dict[str, Any]]]:
    """
    Build a nested map: entity_type -> bundle -> field_name -> field_definition.
    Handles multiple schema shapes (content-model-schema.json variants).
    """
    field_map: Dict[str, Dict[str, Dict[str, Any]]] = {}
    entity_types = schema.get("entity_types", {})

    for etype_name, etype_def in entity_types.items():
        field_map[etype_name] = {}
        bundles = etype_def.get("bundles", {})
        for bundle_name, bundle_def in bundles.items():
            fields = bundle_def.get("fields", {})
            field_map[etype_name][bundle_name] = fields

    return field_map


def collect_known_ids(export: Dict[str, Any]) -> Set[str]:
    """Collect all entity IDs present in the export for reference validation."""
    ids: Set[str] = set()
    entities = _extract_entities(export)
    for entity in entities:
        eid = _get_entity_id(entity)
        if eid:
            ids.add(eid)
        uuid = entity.get("uuid")
        if isinstance(uuid, str):
            ids.add(uuid)
        elif isinstance(uuid, list) and uuid:
            val = uuid[0].get("value") if isinstance(uuid[0], dict) else uuid[0]
            if isinstance(val, str):
                ids.add(val)
    return ids


# ---------------------------------------------------------------------------
# Entity extraction helpers
# ---------------------------------------------------------------------------

def _extract_entities(export: Dict[str, Any]) -> List[Dict[str, Any]]:
    """Extract a flat list of entities from various export formats."""
    # Format 1: {"data": [...entities...]}
    if "data" in export and isinstance(export["data"], list):
        return export["data"]

    # Format 2: {"entities": {...type: [...entities...]...}}
    if "entities" in export and isinstance(export["entities"], dict):
        result = []
        for etype_entities in export["entities"].values():
            if isinstance(etype_entities, list):
                result.extend(etype_entities)
            elif isinstance(etype_entities, dict):
                for bundle_entities in etype_entities.values():
                    if isinstance(bundle_entities, list):
                        result.extend(bundle_entities)
        return result

    # Format 3: {entity_type: {bundle: [...entities...]}}
    result = []
    for key, value in export.items():
        if key.startswith("$") or key.startswith("_") or key in ("meta", "links", "jsonapi"):
            continue
        if isinstance(value, dict):
            for subkey, subval in value.items():
                if isinstance(subval, list):
                    result.extend(e for e in subval if isinstance(e, dict))
        elif isinstance(value, list):
            result.extend(e for e in value if isinstance(e, dict))
    return result


def _get_entity_type_bundle(entity: Dict[str, Any]) -> Tuple[str, str]:
    """Extract entity type and bundle from an entity dict."""
    # JSON:API style: type = "node--article"
    type_str = entity.get("type", "")
    if isinstance(type_str, str) and "--" in type_str:
        parts = type_str.split("--", 1)
        return parts[0], parts[1]

    # Explicit keys
    etype = entity.get("entity_type", entity.get("entityType", ""))
    bundle = entity.get("bundle", entity.get("content_type", ""))

    # Bundle may be nested: {"target_id": "article"}
    if isinstance(bundle, dict):
        bundle = bundle.get("target_id", bundle.get("value", ""))
    if isinstance(bundle, list) and bundle:
        first = bundle[0]
        if isinstance(first, dict):
            bundle = first.get("target_id", first.get("value", ""))
        else:
            bundle = str(first)

    return str(etype), str(bundle)


def _get_entity_id(entity: Dict[str, Any]) -> str:
    """Get the entity ID as a string."""
    for key in ("id", "nid", "tid", "mid", "uid", "fid"):
        val = entity.get(key)
        if val is not None:
            if isinstance(val, list) and val:
                first = val[0]
                if isinstance(first, dict):
                    return str(first.get("value", ""))
                return str(first)
            return str(val)
    return ""


# ---------------------------------------------------------------------------
# Validation passes
# ---------------------------------------------------------------------------

def validate_structure(
    export: Dict[str, Any],
    report: ValidationReport,
) -> None:
    """Check that the export has a recognizable structure."""
    entities = _extract_entities(export)
    if not entities:
        report.error("structure", "Export contains no extractable entities.")
        return
    report.info("structure", f"Found {len(entities)} entities in export.")


def validate_schema_coverage(
    export: Dict[str, Any],
    field_map: Dict[str, Dict[str, Dict[str, Any]]],
    report: ValidationReport,
) -> None:
    """Check every entity has a matching schema definition."""
    entities = _extract_entities(export)
    missing_types: Set[Tuple[str, str]] = set()

    for entity in entities:
        etype, bundle = _get_entity_type_bundle(entity)
        if not etype:
            report.warning(
                "schema",
                "Entity missing type information.",
                entity_id=_get_entity_id(entity),
            )
            continue

        report.entity_counts[etype][bundle or "(no bundle)"] += 1

        if etype not in field_map:
            missing_types.add((etype, ""))
        elif bundle and bundle not in field_map.get(etype, {}):
            missing_types.add((etype, bundle))

    for etype, bundle in sorted(missing_types):
        msg = f"Entity type '{etype}'"
        if bundle:
            msg += f" bundle '{bundle}'"
        msg += " found in export but not in schema."
        report.warning("schema", msg, entity_type=etype, bundle=bundle)


def validate_required_fields(
    export: Dict[str, Any],
    field_map: Dict[str, Dict[str, Dict[str, Any]]],
    report: ValidationReport,
    sample_size: int = 0,
) -> None:
    """Check that required fields are present and non-empty."""
    entities = _extract_entities(export)
    if sample_size > 0 and len(entities) > sample_size:
        import random
        entities = random.sample(entities, sample_size)

    for entity in entities:
        etype, bundle = _get_entity_type_bundle(entity)
        if not etype or not bundle:
            continue

        bundle_fields = field_map.get(etype, {}).get(bundle, {})
        eid = _get_entity_id(entity)

        for field_name, field_def in bundle_fields.items():
            required = field_def.get("required", False)
            if not required:
                continue

            value = entity.get(field_name)
            if value is None:
                report.error(
                    "required_field",
                    f"Required field '{field_name}' is missing.",
                    entity_type=etype,
                    bundle=bundle,
                    entity_id=eid,
                    field=field_name,
                )
            elif _is_empty(value):
                report.error(
                    "required_field",
                    f"Required field '{field_name}' is empty.",
                    entity_type=etype,
                    bundle=bundle,
                    entity_id=eid,
                    field=field_name,
                )


def validate_field_types(
    export: Dict[str, Any],
    field_map: Dict[str, Dict[str, Dict[str, Any]]],
    report: ValidationReport,
    sample_size: int = 0,
) -> None:
    """Spot-check that field values match their expected types."""
    type_validators = {
        "string": _is_string_like,
        "text": _is_string_like,
        "text_long": _is_string_like,
        "text_with_summary": _is_string_like,
        "string_long": _is_string_like,
        "integer": _is_integer_like,
        "decimal": _is_numeric_like,
        "float": _is_numeric_like,
        "boolean": _is_boolean_like,
        "datetime": _is_datetime_like,
        "timestamp": _is_integer_like,
        "uri": _is_string_like,
        "email": _is_email_like,
        "link": _is_link_like,
        "entity_reference": _is_reference_like,
        "entity_reference_revisions": _is_reference_like,
        "image": _is_reference_like,
        "file": _is_reference_like,
    }

    entities = _extract_entities(export)
    if sample_size > 0 and len(entities) > sample_size:
        import random
        entities = random.sample(entities, sample_size)

    for entity in entities:
        etype, bundle = _get_entity_type_bundle(entity)
        if not etype or not bundle:
            continue

        bundle_fields = field_map.get(etype, {}).get(bundle, {})
        eid = _get_entity_id(entity)

        for field_name, field_def in bundle_fields.items():
            value = entity.get(field_name)
            if value is None or _is_empty(value):
                continue

            field_type = field_def.get("type", field_def.get("field_type", ""))
            validator = type_validators.get(field_type)
            if validator and not validator(value):
                report.warning(
                    "field_type",
                    f"Field '{field_name}' expected type '{field_type}' "
                    f"but value does not match.",
                    entity_type=etype,
                    bundle=bundle,
                    entity_id=eid,
                    field=field_name,
                    details={"expected_type": field_type, "actual_sample": _sample_value(value)},
                )
                report.field_type_counts[f"mismatch:{field_type}"] += 1
            elif validator:
                report.field_type_counts[f"ok:{field_type}"] += 1


def validate_cardinality(
    export: Dict[str, Any],
    field_map: Dict[str, Dict[str, Dict[str, Any]]],
    report: ValidationReport,
    sample_size: int = 0,
) -> None:
    """Check multi-value fields respect their cardinality limits."""
    entities = _extract_entities(export)
    if sample_size > 0 and len(entities) > sample_size:
        import random
        entities = random.sample(entities, sample_size)

    for entity in entities:
        etype, bundle = _get_entity_type_bundle(entity)
        if not etype or not bundle:
            continue

        bundle_fields = field_map.get(etype, {}).get(bundle, {})
        eid = _get_entity_id(entity)

        for field_name, field_def in bundle_fields.items():
            cardinality = field_def.get("cardinality", -1)
            if cardinality == -1:  # unlimited
                continue

            value = entity.get(field_name)
            if value is None:
                continue

            count = len(value) if isinstance(value, list) else 1
            if count > cardinality:
                report.error(
                    "cardinality",
                    f"Field '{field_name}' has {count} values but "
                    f"cardinality limit is {cardinality}.",
                    entity_type=etype,
                    bundle=bundle,
                    entity_id=eid,
                    field=field_name,
                    details={"cardinality": cardinality, "actual_count": count},
                )


def validate_entity_references(
    export: Dict[str, Any],
    field_map: Dict[str, Dict[str, Dict[str, Any]]],
    known_ids: Set[str],
    report: ValidationReport,
    sample_size: int = 0,
) -> None:
    """Check that entity reference fields point to existing entities."""
    entities = _extract_entities(export)
    if sample_size > 0 and len(entities) > sample_size:
        import random
        entities = random.sample(entities, sample_size)

    dangling_count = 0
    checked_count = 0

    for entity in entities:
        etype, bundle = _get_entity_type_bundle(entity)
        if not etype or not bundle:
            continue

        bundle_fields = field_map.get(etype, {}).get(bundle, {})
        eid = _get_entity_id(entity)

        for field_name, field_def in bundle_fields.items():
            field_type = field_def.get("type", field_def.get("field_type", ""))
            if field_type not in ("entity_reference", "entity_reference_revisions", "image", "file"):
                continue

            value = entity.get(field_name)
            if value is None or _is_empty(value):
                continue

            target_ids = _extract_reference_ids(value)
            for tid in target_ids:
                checked_count += 1
                if tid not in known_ids:
                    dangling_count += 1
                    if dangling_count <= 100:  # cap individual findings
                        report.warning(
                            "reference",
                            f"Field '{field_name}' references ID '{tid}' "
                            f"which is not in the export.",
                            entity_type=etype,
                            bundle=bundle,
                            entity_id=eid,
                            field=field_name,
                        )

    if dangling_count > 0:
        report.info(
            "reference",
            f"Checked {checked_count} entity references. "
            f"{dangling_count} dangling references found.",
        )
    else:
        report.info(
            "reference",
            f"Checked {checked_count} entity references. All resolve.",
        )


def validate_duplicates(
    export: Dict[str, Any],
    report: ValidationReport,
) -> None:
    """Detect duplicate entity IDs within the export."""
    entities = _extract_entities(export)
    seen: Dict[str, List[str]] = defaultdict(list)

    for entity in entities:
        eid = _get_entity_id(entity)
        if not eid:
            continue
        etype, bundle = _get_entity_type_bundle(entity)
        key = f"{etype}:{eid}"
        seen[key].append(bundle)

    dup_count = 0
    for key, bundles in seen.items():
        if len(bundles) > 1:
            dup_count += 1
            etype, eid = key.split(":", 1)
            report.error(
                "duplicate",
                f"Entity ID '{eid}' appears {len(bundles)} times.",
                entity_type=etype,
                entity_id=eid,
            )

    if dup_count > 0:
        report.info("duplicate", f"Found {dup_count} duplicate entity IDs.")


# ---------------------------------------------------------------------------
# Type checking helpers
# ---------------------------------------------------------------------------

def _is_empty(value: Any) -> bool:
    if value is None:
        return True
    if isinstance(value, str):
        return value.strip() == ""
    if isinstance(value, list):
        return len(value) == 0
    if isinstance(value, dict):
        # Check Drupal field format: [{"value": ""}]
        if "value" in value:
            return _is_empty(value["value"])
        return len(value) == 0
    return False


def _unwrap_value(value: Any) -> Any:
    """Unwrap Drupal field array format to the raw value."""
    if isinstance(value, list) and len(value) == 1 and isinstance(value[0], dict):
        if "value" in value[0]:
            return value[0]["value"]
    if isinstance(value, dict) and "value" in value:
        return value["value"]
    return value


def _is_string_like(value: Any) -> bool:
    v = _unwrap_value(value)
    return isinstance(v, str)


def _is_integer_like(value: Any) -> bool:
    v = _unwrap_value(value)
    if isinstance(v, int):
        return True
    if isinstance(v, str):
        try:
            int(v)
            return True
        except ValueError:
            return False
    return False


def _is_numeric_like(value: Any) -> bool:
    v = _unwrap_value(value)
    if isinstance(v, (int, float)):
        return True
    if isinstance(v, str):
        try:
            float(v)
            return True
        except ValueError:
            return False
    return False


def _is_boolean_like(value: Any) -> bool:
    v = _unwrap_value(value)
    if isinstance(v, bool):
        return True
    if isinstance(v, (int, str)):
        return str(v).lower() in ("0", "1", "true", "false", "yes", "no")
    return False


def _is_datetime_like(value: Any) -> bool:
    v = _unwrap_value(value)
    if not isinstance(v, str):
        return False
    # ISO 8601 patterns
    patterns = [
        r"^\d{4}-\d{2}-\d{2}$",
        r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}",
        r"^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}",
    ]
    return any(re.match(p, v) for p in patterns)


def _is_email_like(value: Any) -> bool:
    v = _unwrap_value(value)
    if not isinstance(v, str):
        return False
    return bool(re.match(r"^[^@\s]+@[^@\s]+\.[^@\s]+$", v))


def _is_link_like(value: Any) -> bool:
    v = _unwrap_value(value)
    if isinstance(v, dict):
        return "uri" in v or "url" in v or "href" in v
    if isinstance(v, list) and v and isinstance(v[0], dict):
        return "uri" in v[0] or "url" in v[0]
    return False


def _is_reference_like(value: Any) -> bool:
    if isinstance(value, dict):
        return any(k in value for k in ("target_id", "id", "data", "uuid"))
    if isinstance(value, list):
        return all(_is_reference_like(item) for item in value if isinstance(item, dict))
    return False


def _extract_reference_ids(value: Any) -> List[str]:
    """Pull target IDs from reference field values."""
    ids: List[str] = []
    items = value if isinstance(value, list) else [value]
    for item in items:
        if not isinstance(item, dict):
            continue
        for key in ("target_id", "id", "uuid"):
            val = item.get(key)
            if val is not None:
                ids.append(str(val))
                break
        # JSON:API nested data
        data = item.get("data")
        if isinstance(data, dict) and "id" in data:
            ids.append(str(data["id"]))
        elif isinstance(data, list):
            for d in data:
                if isinstance(d, dict) and "id" in d:
                    ids.append(str(d["id"]))
    return ids


def _sample_value(value: Any) -> str:
    """Produce a short string sample of a value for reporting."""
    s = str(value)
    if len(s) > 120:
        return s[:120] + "..."
    return s


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def parse_args(argv: Optional[List[str]] = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Validate a Drupal content export against the content model schema."
    )
    parser.add_argument(
        "--export",
        required=True,
        type=Path,
        help="Path to the JSON content export file.",
    )
    parser.add_argument(
        "--schema",
        required=True,
        type=Path,
        help="Path to the content-model-schema.json file.",
    )
    parser.add_argument(
        "--output",
        type=Path,
        default=None,
        help="Write report to this file (default: stdout).",
    )
    parser.add_argument(
        "--format",
        choices=["json", "text"],
        default="json",
        help="Output format (default: json).",
    )
    parser.add_argument(
        "--sample",
        type=int,
        default=0,
        help="Sample N entities for field checks (0 = all, default: 0).",
    )
    parser.add_argument(
        "--strict",
        action="store_true",
        help="Exit with code 1 if any warnings are found (not just errors).",
    )
    parser.add_argument(
        "--verbose",
        action="store_true",
        help="Print progress to stderr.",
    )
    return parser.parse_args(argv)


def main(argv: Optional[List[str]] = None) -> int:
    args = parse_args(argv)

    def log(msg: str) -> None:
        if args.verbose:
            print(f"[validate-export] {msg}", file=sys.stderr)

    # Load inputs
    log(f"Loading schema from {args.schema}")
    try:
        schema = load_schema(args.schema)
    except (json.JSONDecodeError, ValueError) as e:
        print(f"Error loading schema: {e}", file=sys.stderr)
        return 2

    log(f"Loading export from {args.export}")
    try:
        export = load_export(args.export)
    except json.JSONDecodeError as e:
        print(f"Error loading export: {e}", file=sys.stderr)
        return 2

    field_map = build_field_map(schema)
    report = ValidationReport()

    # Run validation passes
    log("Checking export structure...")
    validate_structure(export, report)

    log("Checking schema coverage...")
    validate_schema_coverage(export, field_map, report)

    log("Checking for duplicate entities...")
    validate_duplicates(export, report)

    log("Checking required fields...")
    validate_required_fields(export, field_map, report, sample_size=args.sample)

    log("Checking field types...")
    validate_field_types(export, field_map, report, sample_size=args.sample)

    log("Checking cardinality...")
    validate_cardinality(export, field_map, report, sample_size=args.sample)

    log("Checking entity references...")
    known_ids = collect_known_ids(export)
    validate_entity_references(export, field_map, known_ids, report, sample_size=args.sample)

    report.finalize()

    # Output
    if args.format == "json":
        output_str = json.dumps(report.to_dict(), indent=2)
    else:
        output_str = report.to_text()

    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        with open(args.output, "w", encoding="utf-8") as f:
            f.write(output_str)
        log(f"Report written to {args.output}")
    else:
        print(output_str)

    # Exit code
    if report.error_count > 0:
        return 1
    if args.strict and report.warning_count > 0:
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
