#!/usr/bin/env python3
"""
flatten-paragraphs.py — Flatten nested Drupal paragraph trees into portable components.

Drupal stores content as deeply nested paragraph entities that reference other
paragraph entities via entity_reference_revisions fields. This script takes a
JSON export containing those nested structures and produces a flat array of
typed components with all field values resolved inline.

Input:  JSON export with nested paragraph references (from skill 12 output).
Output: Flat array of typed components with resolved field values.

Usage:
    python flatten-paragraphs.py --input paragraphs.json --output flat.json
    python flatten-paragraphs.py --input paragraphs.json --output flat.json --max-depth 10 --verbose
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any, Dict, List, Optional


# Fields that indicate a nested paragraph reference
PARAGRAPH_REF_INDICATORS = {
    "entity_reference_revisions",
    "entity_reference_revision",
}

# Fields on paragraph entities that are structural, not content
STRUCTURAL_FIELDS = {
    "id",
    "uuid",
    "revision_id",
    "langcode",
    "type",
    "status",
    "created",
    "changed",
    "parent_id",
    "parent_type",
    "parent_field_name",
    "default_langcode",
    "revision_default",
    "revision_translation_affected",
    "behavior_settings",
    "content_translation_source",
    "content_translation_outdated",
    "content_translation_changed",
}


def is_paragraph_reference(field_value: Any) -> bool:
    """Check if a field value looks like a paragraph entity reference."""
    if isinstance(field_value, dict):
        # JSON:API style: {"data": {"type": "paragraph--*", ...}}
        data = field_value.get("data")
        if isinstance(data, dict):
            ptype = data.get("type", "")
            if isinstance(ptype, str) and ptype.startswith("paragraph--"):
                return True
        if isinstance(data, list):
            return any(
                isinstance(item, dict)
                and isinstance(item.get("type", ""), str)
                and item["type"].startswith("paragraph--")
                for item in data
            )
        # Direct paragraph structure
        if "type" in field_value and isinstance(field_value.get("type"), str):
            if field_value["type"].startswith("paragraph--"):
                return True
        if field_value.get("target_type") == "paragraph":
            return True
    if isinstance(field_value, list):
        return any(is_paragraph_reference(item) for item in field_value)
    return False


def resolve_entity_ref(ref: Dict[str, Any], verbose: bool = False) -> Any:
    """Resolve a single entity reference to a human-readable value."""
    # If it has resolved attributes/fields already embedded, use those
    if "attributes" in ref:
        attrs = ref["attributes"]
        for key in ("name", "title", "label", "filename", "uri"):
            if key in attrs:
                return attrs[key]
        return attrs
    if "meta" in ref:
        meta = ref["meta"]
        for key in ("title", "description", "alt", "display_name"):
            if key in meta:
                return meta[key]
    # Fallback: return the reference identifiers
    result: Dict[str, Any] = {}
    for key in ("id", "uuid", "target_id", "target_uuid", "type"):
        if key in ref:
            result[key] = ref[key]
    return result if result else ref


def extract_field_value(field_name: str, field_value: Any) -> Any:
    """Extract a clean value from a Drupal field structure."""
    if field_value is None:
        return None

    # Drupal field arrays: [{"value": "...", "format": "..."}]
    if isinstance(field_value, list):
        if len(field_value) == 0:
            return []
        if len(field_value) == 1 and isinstance(field_value[0], dict):
            item = field_value[0]
            if "value" in item and len(item) <= 3:
                return item["value"]
        cleaned = []
        for item in field_value:
            if isinstance(item, dict):
                if "value" in item and len(item) <= 3:
                    cleaned.append(item["value"])
                elif "uri" in item:
                    cleaned.append({
                        "uri": item.get("uri"),
                        "title": item.get("title"),
                        "options": item.get("options"),
                    })
                else:
                    cleaned.append(item)
            else:
                cleaned.append(item)
        return cleaned

    # Single dict with "value" key
    if isinstance(field_value, dict):
        if "value" in field_value and len(field_value) <= 3:
            return field_value["value"]
        # JSON:API entity reference
        if "data" in field_value:
            data = field_value["data"]
            if isinstance(data, dict):
                return resolve_entity_ref(data)
            if isinstance(data, list):
                return [resolve_entity_ref(d) for d in data if isinstance(d, dict)]
        # Link field
        if "uri" in field_value:
            return {
                "uri": field_value.get("uri"),
                "title": field_value.get("title"),
            }

    return field_value


def flatten_paragraph(
    paragraph: Dict[str, Any],
    parent_field: Optional[str] = None,
    depth: int = 0,
    max_depth: int = 20,
    order: List[int] = None,
    verbose: bool = False,
) -> List[Dict[str, Any]]:
    """
    Recursively flatten a paragraph entity into a list of typed components.

    Each component gets:
      - type: the paragraph bundle name
      - depth: nesting level (0 = top-level)
      - order: positional path in the tree (e.g. [0, 2, 1])
      - parent_field: which field on the parent held this paragraph
      - fields: dict of resolved field values (non-structural, non-reference)
      - children: count of direct child paragraphs
    """
    if order is None:
        order = []

    if depth > max_depth:
        if verbose:
            print(
                f"[flatten] Max depth {max_depth} reached, skipping deeper nesting",
                file=sys.stderr,
            )
        return []

    results: List[Dict[str, Any]] = []

    # Determine paragraph type
    ptype = paragraph.get("type", "unknown")
    # JSON:API format: "paragraph--hero_banner"
    if isinstance(ptype, str) and "--" in ptype:
        ptype = ptype.split("--", 1)[1]
    # Nested type object: {"target_id": "hero_banner"}
    if isinstance(ptype, dict):
        ptype = ptype.get("target_id", ptype.get("id", "unknown"))
    # Array of type objects from Drupal export
    if isinstance(ptype, list) and len(ptype) > 0:
        first = ptype[0]
        if isinstance(first, dict):
            ptype = first.get("target_id", "unknown")
        else:
            ptype = str(first)

    # Gather fields: either under "attributes" (JSON:API) or top-level
    raw_fields = paragraph.get("attributes", paragraph)
    if not isinstance(raw_fields, dict):
        raw_fields = paragraph

    resolved_fields: Dict[str, Any] = {}
    child_paragraphs: List[Dict[str, Any]] = []
    child_count = 0

    for field_name, field_value in raw_fields.items():
        if field_name in STRUCTURAL_FIELDS:
            continue
        if field_name == "type":
            continue

        # Check for nested paragraph references
        if is_paragraph_reference(field_value):
            nested = _extract_nested_paragraphs(field_value)
            for idx, nested_para in enumerate(nested):
                child_paragraphs.append({
                    "paragraph": nested_para,
                    "field": field_name,
                    "index": idx,
                })
            child_count += len(nested)
        else:
            resolved_fields[field_name] = extract_field_value(field_name, field_value)

    # Also check "relationships" (JSON:API compound documents)
    relationships = paragraph.get("relationships", {})
    for rel_name, rel_value in relationships.items():
        if not isinstance(rel_value, dict):
            continue
        rel_data = rel_value.get("data")
        if rel_data is None:
            continue
        # Check if this relationship points to paragraphs
        items = rel_data if isinstance(rel_data, list) else [rel_data]
        paragraph_items = [
            item for item in items
            if isinstance(item, dict)
            and isinstance(item.get("type", ""), str)
            and item["type"].startswith("paragraph--")
        ]
        if paragraph_items:
            for idx, item in enumerate(paragraph_items):
                # Resolve from "included" if available
                resolved = item.get("_resolved", item)
                child_paragraphs.append({
                    "paragraph": resolved,
                    "field": rel_name,
                    "index": idx,
                })
            child_count += len(paragraph_items)
        else:
            # Non-paragraph relationship — resolve it
            if len(items) == 1:
                resolved_fields[rel_name] = resolve_entity_ref(items[0])
            else:
                resolved_fields[rel_name] = [
                    resolve_entity_ref(item) for item in items
                    if isinstance(item, dict)
                ]

    # Build this component
    component: Dict[str, Any] = {
        "type": ptype,
        "depth": depth,
        "order": list(order),
        "fields": resolved_fields,
        "children": child_count,
    }
    if parent_field:
        component["parent_field"] = parent_field

    # Preserve IDs for traceability
    for id_field in ("id", "uuid"):
        val = paragraph.get(id_field) or raw_fields.get(id_field)
        if val:
            component[id_field] = val

    results.append(component)

    if verbose and depth == 0:
        print(f"[flatten] Processing {ptype} with {child_count} children", file=sys.stderr)

    # Recurse into children
    for child_info in child_paragraphs:
        child_order = list(order) + [child_info["index"]]
        child_results = flatten_paragraph(
            paragraph=child_info["paragraph"],
            parent_field=child_info["field"],
            depth=depth + 1,
            max_depth=max_depth,
            order=child_order,
            verbose=verbose,
        )
        results.extend(child_results)

    return results


def _extract_nested_paragraphs(field_value: Any) -> List[Dict[str, Any]]:
    """Extract paragraph entity dicts from various reference formats."""
    paragraphs: List[Dict[str, Any]] = []

    if isinstance(field_value, dict):
        data = field_value.get("data")
        if isinstance(data, list):
            paragraphs.extend(item for item in data if isinstance(item, dict))
        elif isinstance(data, dict):
            paragraphs.append(data)
        elif "target_id" in field_value or "type" in field_value:
            paragraphs.append(field_value)
    elif isinstance(field_value, list):
        for item in field_value:
            if isinstance(item, dict):
                if is_paragraph_reference(item):
                    paragraphs.extend(_extract_nested_paragraphs(item))
                elif item.get("target_type") == "paragraph" or (
                    isinstance(item.get("type"), str)
                    and item["type"].startswith("paragraph--")
                ):
                    paragraphs.append(item)

    return paragraphs


def flatten_export(
    data: Any,
    max_depth: int = 20,
    verbose: bool = False,
) -> List[Dict[str, Any]]:
    """
    Flatten an entire export file.

    Accepts:
      - A list of paragraph entities (direct export)
      - A JSON:API compound document with "data" and "included"
      - A dict mapping node IDs to paragraph trees
    """
    all_components: List[Dict[str, Any]] = []

    # JSON:API compound document
    if isinstance(data, dict) and "data" in data:
        items = data["data"]
        if not isinstance(items, list):
            items = [items]

        # Build lookup from "included" for resolving nested references
        included_lookup: Dict[str, Dict[str, Any]] = {}
        for inc in data.get("included", []):
            if isinstance(inc, dict) and "id" in inc and "type" in inc:
                key = f"{inc['type']}:{inc['id']}"
                included_lookup[key] = inc

        # Resolve _resolved references in included paragraphs
        _resolve_included(items, included_lookup)
        for inc in included_lookup.values():
            _resolve_included_item(inc, included_lookup)

        for item in items:
            if isinstance(item, dict):
                components = flatten_paragraph(
                    paragraph=item,
                    max_depth=max_depth,
                    verbose=verbose,
                )
                all_components.extend(components)

    # List of paragraph entities
    elif isinstance(data, list):
        for idx, item in enumerate(data):
            if isinstance(item, dict):
                components = flatten_paragraph(
                    paragraph=item,
                    max_depth=max_depth,
                    order=[idx],
                    verbose=verbose,
                )
                all_components.extend(components)

    # Dict mapping content IDs to paragraph arrays
    elif isinstance(data, dict):
        for content_id, paragraphs in data.items():
            if isinstance(paragraphs, list):
                for idx, para in enumerate(paragraphs):
                    if isinstance(para, dict):
                        components = flatten_paragraph(
                            paragraph=para,
                            max_depth=max_depth,
                            order=[idx],
                            verbose=verbose,
                        )
                        for comp in components:
                            comp["content_id"] = content_id
                        all_components.extend(components)

    return all_components


def _resolve_included(items: List[Any], lookup: Dict[str, Dict[str, Any]]) -> None:
    """Attach _resolved data from included to relationship references."""
    for item in items:
        if isinstance(item, dict):
            _resolve_included_item(item, lookup)


def _resolve_included_item(item: Dict[str, Any], lookup: Dict[str, Dict[str, Any]]) -> None:
    """Resolve included references on a single item."""
    relationships = item.get("relationships", {})
    for rel_name, rel_value in relationships.items():
        if not isinstance(rel_value, dict):
            continue
        rel_data = rel_value.get("data")
        if rel_data is None:
            continue
        refs = rel_data if isinstance(rel_data, list) else [rel_data]
        for ref in refs:
            if isinstance(ref, dict) and "type" in ref and "id" in ref:
                key = f"{ref['type']}:{ref['id']}"
                if key in lookup:
                    ref["_resolved"] = lookup[key]


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Flatten nested Drupal paragraph trees into portable components.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=(
            "Examples:\n"
            "  python flatten-paragraphs.py --input paragraphs.json --output flat.json\n"
            "  python flatten-paragraphs.py --input export.json --output flat.json --max-depth 10 --verbose\n"
        ),
    )
    parser.add_argument(
        "--input", required=True,
        help="Path to JSON file with nested paragraph data",
    )
    parser.add_argument(
        "--output", required=True,
        help="Path to write flattened component JSON",
    )
    parser.add_argument(
        "--max-depth", type=int, default=20,
        help="Maximum nesting depth to traverse (default: 20)",
    )
    parser.add_argument(
        "--verbose", action="store_true",
        help="Print progress to stderr",
    )
    args = parser.parse_args()

    input_path = Path(args.input)
    if not input_path.exists():
        print(f"Error: input file not found: {input_path}", file=sys.stderr)
        sys.exit(1)

    if args.verbose:
        print(f"[flatten] Reading {input_path}", file=sys.stderr)

    try:
        with open(input_path, "r", encoding="utf-8") as f:
            data = json.load(f)
    except json.JSONDecodeError as exc:
        print(f"Error: invalid JSON in {input_path}: {exc}", file=sys.stderr)
        sys.exit(1)

    components = flatten_export(data, max_depth=args.max_depth, verbose=args.verbose)

    if args.verbose:
        types = {}
        for comp in components:
            t = comp.get("type", "unknown")
            types[t] = types.get(t, 0) + 1
        print(f"[flatten] Produced {len(components)} components:", file=sys.stderr)
        for t, count in sorted(types.items()):
            print(f"[flatten]   {t}: {count}", file=sys.stderr)

    output_path = Path(args.output)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    with open(output_path, "w", encoding="utf-8") as f:
        json.dump(components, f, indent=2, ensure_ascii=False)

    if args.verbose:
        print(f"[flatten] Wrote {output_path}", file=sys.stderr)


if __name__ == "__main__":
    main()
