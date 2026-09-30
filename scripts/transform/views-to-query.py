#!/usr/bin/env python3
"""
views-to-query.py — Convert Drupal Views YAML to abstract query definitions.

Drupal Views encode complex query logic (filters, sorts, relationships, pagers)
in YAML config files. This script parses views.view.*.yml files and produces
portable JSON query definitions that any target platform can consume.

Usage:
    python views-to-query.py --input-dir config/sync --output queries.json
    python views-to-query.py --input-dir config/sync --output queries.json --verbose
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path
from typing import Any, Dict, List, Optional

try:
    import yaml
except ImportError:
    yaml = None  # type: ignore[assignment]


# Map Drupal base_table to entity type
BASE_TABLE_ENTITY_MAP: Dict[str, str] = {
    "node_field_data": "node",
    "node": "node",
    "taxonomy_term_field_data": "taxonomy_term",
    "taxonomy_term_data": "taxonomy_term",
    "users_field_data": "user",
    "users": "user",
    "media_field_data": "media",
    "file_managed": "file",
    "comment_field_data": "comment",
    "comment": "comment",
    "block_content_field_data": "block_content",
    "commerce_product_field_data": "commerce_product",
    "commerce_product_variation_field_data": "commerce_product_variation",
    "commerce_order": "commerce_order",
    "paragraphs_item_field_data": "paragraph",
    "redirect": "redirect",
    "path_alias": "path_alias",
    "webform_submission": "webform_submission",
    "flagging": "flagging",
    "search_api_index_*": "search_api",
}

# Map Drupal filter operators to abstract operators
OPERATOR_MAP: Dict[str, str] = {
    "=": "equals",
    "!=": "not_equals",
    "<>": "not_equals",
    "<": "less_than",
    "<=": "less_than_or_equal",
    ">": "greater_than",
    ">=": "greater_than_or_equal",
    "in": "in",
    "not in": "not_in",
    "LIKE": "contains",
    "like": "contains",
    "NOT LIKE": "not_contains",
    "not like": "not_contains",
    "starts": "starts_with",
    "ends": "ends_with",
    "BETWEEN": "between",
    "between": "between",
    "NOT BETWEEN": "not_between",
    "IS NULL": "is_null",
    "is null": "is_null",
    "IS NOT NULL": "is_not_null",
    "is not null": "is_not_null",
    "regular_expression": "regex",
    "empty": "is_empty",
    "not empty": "is_not_empty",
    "contains": "contains",
    "word": "contains_word",
    "allwords": "contains_all_words",
    "shorterthan": "shorter_than",
    "longerthan": "longer_than",
}


def resolve_entity_type(base_table: str) -> str:
    """Resolve a Drupal base_table to an entity type name."""
    if base_table in BASE_TABLE_ENTITY_MAP:
        return BASE_TABLE_ENTITY_MAP[base_table]
    # Search API indexes
    if base_table.startswith("search_api_index_"):
        return "search_api"
    return base_table


def parse_filter(
    filter_id: str,
    filter_config: Dict[str, Any],
) -> Dict[str, Any]:
    """Parse a single Views filter into an abstract condition."""
    plugin_id = filter_config.get("plugin_id", "")
    field = filter_config.get("field", filter_id)
    table = filter_config.get("table", "")

    # Build the field reference
    if "." in field:
        field_ref = field
    elif table:
        field_ref = f"{table}.{field}"
    else:
        field_ref = field

    operator = filter_config.get("operator", "=")
    abstract_op = OPERATOR_MAP.get(operator, operator)

    condition: Dict[str, Any] = {
        "field": field_ref,
        "operator": abstract_op,
    }

    # Value
    value = filter_config.get("value", {})
    if isinstance(value, dict):
        # Multi-value filters (e.g., content type selection)
        active_values = [k for k, v in value.items() if v]
        if active_values:
            condition["value"] = active_values if len(active_values) > 1 else active_values[0]
        elif value:
            # All-value dicts like {"min": "", "max": "", "value": "..."}
            if "value" in value:
                condition["value"] = value["value"]
            else:
                condition["value"] = value
    elif value is not None:
        condition["value"] = value

    # Exposed filter metadata
    expose = filter_config.get("expose", {})
    if expose and expose.get("identifier"):
        condition["exposed"] = True
        condition["exposed_id"] = expose["identifier"]
        condition["exposed_label"] = expose.get("label", "")
        condition["exposed_required"] = expose.get("required", False)
        if expose.get("multiple"):
            condition["exposed_multiple"] = True

    # Group membership
    group_info = filter_config.get("group_info", {})
    if group_info:
        condition["group"] = group_info

    # Plugin-specific details
    if plugin_id == "bundle":
        condition["type"] = "bundle_filter"
    elif plugin_id == "boolean":
        condition["type"] = "boolean"
    elif plugin_id == "date":
        condition["type"] = "date"
    elif plugin_id == "numeric":
        condition["type"] = "numeric"
    elif plugin_id in ("combine", "search_api_fulltext"):
        condition["type"] = "fulltext"
    else:
        condition["type"] = plugin_id or "standard"

    # Negate
    if filter_config.get("not"):
        condition["negate"] = True

    return condition


def parse_sort(sort_id: str, sort_config: Dict[str, Any]) -> Dict[str, Any]:
    """Parse a single Views sort into an abstract sort definition."""
    field = sort_config.get("field", sort_id)
    table = sort_config.get("table", "")

    if "." in field:
        field_ref = field
    elif table:
        field_ref = f"{table}.{field}"
    else:
        field_ref = field

    sort_def: Dict[str, Any] = {
        "field": field_ref,
        "direction": sort_config.get("order", "ASC").upper(),
    }

    # Exposed sort
    expose = sort_config.get("expose", {})
    if expose and expose.get("label"):
        sort_def["exposed"] = True
        sort_def["exposed_label"] = expose["label"]

    # Granularity for date sorts
    granularity = sort_config.get("granularity")
    if granularity:
        sort_def["granularity"] = granularity

    return sort_def


def parse_relationship(rel_id: str, rel_config: Dict[str, Any]) -> Dict[str, Any]:
    """Parse a Views relationship into an abstract join definition."""
    return {
        "id": rel_id,
        "field": rel_config.get("field", rel_id),
        "table": rel_config.get("table", ""),
        "plugin_id": rel_config.get("plugin_id", "standard"),
        "required": rel_config.get("required", False),
        "admin_label": rel_config.get("admin_label", ""),
    }


def parse_contextual_filter(
    arg_id: str,
    arg_config: Dict[str, Any],
) -> Dict[str, Any]:
    """Parse a Views contextual filter (argument) into an abstract definition."""
    ctx: Dict[str, Any] = {
        "field": arg_config.get("field", arg_id),
        "table": arg_config.get("table", ""),
        "plugin_id": arg_config.get("plugin_id", ""),
    }

    # Default behavior when no argument is provided
    default = arg_config.get("default_action", "ignore")
    ctx["default_action"] = default

    if default == "default":
        default_type = arg_config.get("default_argument_type", "")
        ctx["default_type"] = default_type
        if default_type == "fixed":
            ctx["default_value"] = arg_config.get("default_argument_options", {}).get("argument", "")
        elif default_type == "raw":
            ctx["default_value"] = "url_path_component"

    # Exception behavior
    exception = arg_config.get("exception", {})
    if exception:
        ctx["exception_value"] = exception.get("value", "all")
        ctx["exception_title"] = exception.get("title_enable", False)

    # Validation
    validate = arg_config.get("validate", {})
    if validate and validate.get("type", "none") != "none":
        ctx["validation_type"] = validate["type"]

    return ctx


def parse_pager(pager_config: Dict[str, Any]) -> Dict[str, Any]:
    """Parse Views pager configuration."""
    pager_type = pager_config.get("type", "none")
    options = pager_config.get("options", {})

    pager: Dict[str, Any] = {"type": pager_type}

    if pager_type == "full":
        pager["items_per_page"] = options.get("items_per_page", 10)
        pager["offset"] = options.get("offset", 0)
        if options.get("total_pages"):
            pager["total_pages"] = options["total_pages"]
        if options.get("expose", {}).get("items_per_page"):
            pager["exposed_items_per_page"] = True
    elif pager_type == "mini":
        pager["items_per_page"] = options.get("items_per_page", 10)
        pager["offset"] = options.get("offset", 0)
    elif pager_type == "some":
        pager["items_per_page"] = options.get("items_per_page", 10)
        pager["offset"] = options.get("offset", 0)
    elif pager_type == "none":
        pager["items_per_page"] = 0  # unlimited
        offset = options.get("offset", 0)
        if offset:
            pager["offset"] = offset

    return pager


def parse_fields(fields_config: Dict[str, Any]) -> List[Dict[str, Any]]:
    """Parse Views field configurations into a field list."""
    fields: List[Dict[str, Any]] = []

    for field_id, field_config in fields_config.items():
        field_def: Dict[str, Any] = {
            "id": field_id,
            "field": field_config.get("field", field_id),
            "table": field_config.get("table", ""),
            "plugin_id": field_config.get("plugin_id", "field"),
        }

        label = field_config.get("label", "")
        if label:
            field_def["label"] = label

        # Exclude from display
        if field_config.get("exclude"):
            field_def["exclude"] = True

        # Formatter settings
        formatter = field_config.get("type")
        if formatter:
            field_def["formatter"] = formatter

        settings = field_config.get("settings", {})
        if settings:
            field_def["settings"] = settings

        # Relationship
        relationship = field_config.get("relationship")
        if relationship and relationship != "none":
            field_def["relationship"] = relationship

        # Rewrite
        alter = field_config.get("alter", {})
        if alter and alter.get("alter_text"):
            field_def["rewrite"] = alter.get("text", "")

        fields.append(field_def)

    return fields


def parse_filter_groups(filter_groups: Dict[str, Any]) -> Optional[Dict[str, Any]]:
    """Parse filter group operators (AND/OR)."""
    if not filter_groups:
        return None

    operator = filter_groups.get("operator", "AND")
    groups = filter_groups.get("groups", {})

    if len(groups) <= 1 and operator == "AND":
        return None

    return {
        "operator": operator,
        "groups": {
            str(k): v for k, v in groups.items()
        },
    }


def parse_display(
    display_id: str,
    display_config: Dict[str, Any],
    defaults: Dict[str, Any],
    view_id: str,
    verbose: bool = False,
) -> Dict[str, Any]:
    """Parse a single Views display into a query definition."""
    display_plugin = display_config.get("display_plugin", "unknown")
    options = display_config.get("display_options", {})

    # Merge with defaults — display options override defaults
    def get_option(key: str) -> Any:
        if key in options:
            return options[key]
        return defaults.get(key)

    query_def: Dict[str, Any] = {
        "view_id": view_id,
        "display_id": display_id,
        "display_type": display_plugin,
        "title": options.get("title", defaults.get("title", "")),
    }

    # Path (for page, feed, rest_export displays)
    path = options.get("path")
    if path:
        query_def["path"] = f"/{path}" if not path.startswith("/") else path

    # Entity type — derived from base_table at the view level
    # (passed in via the caller)

    # Fields
    fields_config = get_option("fields")
    if fields_config and isinstance(fields_config, dict):
        query_def["fields"] = parse_fields(fields_config)

    # Filters / conditions
    filters_config = get_option("filters")
    if filters_config and isinstance(filters_config, dict):
        conditions = []
        bundle_filters: List[str] = []
        for fid, fconfig in filters_config.items():
            if not isinstance(fconfig, dict):
                continue
            condition = parse_filter(fid, fconfig)
            conditions.append(condition)
            # Extract bundle filter for top-level convenience
            if condition.get("type") == "bundle_filter" and "value" in condition:
                val = condition["value"]
                if isinstance(val, list):
                    bundle_filters.extend(val)
                elif isinstance(val, str):
                    bundle_filters.append(val)
        query_def["conditions"] = conditions
        if bundle_filters:
            query_def["bundle_filter"] = bundle_filters

    # Filter groups
    filter_groups = get_option("filter_groups")
    if filter_groups:
        parsed_groups = parse_filter_groups(filter_groups)
        if parsed_groups:
            query_def["filter_groups"] = parsed_groups

    # Sorts
    sorts_config = get_option("sorts")
    if sorts_config and isinstance(sorts_config, dict):
        query_def["sort"] = [
            parse_sort(sid, sconfig)
            for sid, sconfig in sorts_config.items()
            if isinstance(sconfig, dict)
        ]

    # Relationships (joins)
    rels_config = get_option("relationships")
    if rels_config and isinstance(rels_config, dict):
        query_def["relationships"] = [
            parse_relationship(rid, rconfig)
            for rid, rconfig in rels_config.items()
            if isinstance(rconfig, dict)
        ]

    # Contextual filters (arguments)
    args_config = get_option("arguments")
    if args_config and isinstance(args_config, dict):
        query_def["contextual_filters"] = [
            parse_contextual_filter(aid, aconfig)
            for aid, aconfig in args_config.items()
            if isinstance(aconfig, dict)
        ]

    # Pager
    pager_config = get_option("pager")
    if pager_config and isinstance(pager_config, dict):
        query_def["pager"] = parse_pager(pager_config)

    # Header / footer / empty text
    for section in ("header", "footer", "empty"):
        section_config = get_option(section)
        if section_config and isinstance(section_config, dict):
            items = []
            for area_id, area_config in section_config.items():
                if isinstance(area_config, dict):
                    items.append({
                        "id": area_id,
                        "plugin_id": area_config.get("plugin_id", ""),
                        "content": area_config.get("content", ""),
                    })
            if items:
                query_def[section] = items

    # Access control
    access_config = get_option("access")
    if access_config and isinstance(access_config, dict):
        access_type = access_config.get("type", "none")
        if access_type != "none":
            query_def["access"] = {
                "type": access_type,
                "options": access_config.get("options", {}),
            }

    # Cache
    cache_config = get_option("cache")
    if cache_config and isinstance(cache_config, dict):
        cache_type = cache_config.get("type", "none")
        if cache_type != "none":
            query_def["cache"] = {
                "type": cache_type,
                "options": cache_config.get("options", {}),
            }

    # Exposed form
    exposed_form = get_option("exposed_form")
    if exposed_form and isinstance(exposed_form, dict):
        ef_type = exposed_form.get("type", "basic")
        if ef_type != "basic":
            query_def["exposed_form"] = {
                "type": ef_type,
                "options": exposed_form.get("options", {}),
            }

    return query_def


def parse_view(
    view_data: Dict[str, Any],
    verbose: bool = False,
) -> Dict[str, Any]:
    """Parse a complete Views YAML into a set of query definitions."""
    view_id = view_data.get("id", "unknown")
    label = view_data.get("label", "")
    description = view_data.get("description", "")
    status = view_data.get("status", True)
    base_table = view_data.get("base_table", "")
    entity_type = resolve_entity_type(base_table)

    if verbose:
        print(f"[views] Parsing view: {view_id} ({label})", file=sys.stderr)

    displays = view_data.get("display", {})
    default_display = displays.get("default", {})
    default_options = default_display.get("display_options", {})

    parsed_displays: List[Dict[str, Any]] = []

    for display_id, display_config in displays.items():
        if not isinstance(display_config, dict):
            continue

        query_def = parse_display(
            display_id=display_id,
            display_config=display_config,
            defaults=default_options,
            view_id=view_id,
            verbose=verbose,
        )
        query_def["entity_type"] = entity_type
        query_def["base_table"] = base_table
        parsed_displays.append(query_def)

    return {
        "view_id": view_id,
        "label": label,
        "description": description,
        "status": status,
        "entity_type": entity_type,
        "base_table": base_table,
        "module": view_data.get("module", ""),
        "tag": view_data.get("tag", ""),
        "displays": parsed_displays,
    }


def load_yaml_file(path: Path) -> Optional[Dict[str, Any]]:
    """Load a YAML file, trying PyYAML first, falling back to basic parsing."""
    if yaml is not None:
        with open(path, "r", encoding="utf-8") as f:
            return yaml.safe_load(f)

    # Minimal fallback: try to parse as JSON (some exports are JSON)
    with open(path, "r", encoding="utf-8") as f:
        content = f.read()

    try:
        return json.loads(content)
    except json.JSONDecodeError:
        print(
            f"Error: PyYAML is required to parse YAML files.\n"
            f"Install with: pip install pyyaml",
            file=sys.stderr,
        )
        sys.exit(1)


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Convert Drupal Views YAML to abstract query definitions.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=(
            "Examples:\n"
            "  python views-to-query.py --input-dir config/sync --output queries.json\n"
            "  python views-to-query.py --input-dir /path/to/views --output queries.json --verbose\n"
        ),
    )
    parser.add_argument(
        "--input-dir", required=True,
        help="Directory containing views.view.*.yml files",
    )
    parser.add_argument(
        "--output", required=True,
        help="Path to write JSON query definitions",
    )
    parser.add_argument(
        "--verbose", action="store_true",
        help="Print progress to stderr",
    )
    args = parser.parse_args()

    input_dir = Path(args.input_dir)
    if not input_dir.is_dir():
        print(f"Error: input directory not found: {input_dir}", file=sys.stderr)
        sys.exit(1)

    # Find views YAML files
    view_files = sorted(input_dir.glob("views.view.*.yml"))

    # Also check for JSON variants
    view_files.extend(sorted(input_dir.glob("views.view.*.json")))

    if not view_files:
        print(f"Error: no views.view.*.yml files found in {input_dir}", file=sys.stderr)
        sys.exit(1)

    if args.verbose:
        print(f"[views] Found {len(view_files)} view files in {input_dir}", file=sys.stderr)

    all_views: List[Dict[str, Any]] = []

    for view_file in view_files:
        if args.verbose:
            print(f"[views] Processing {view_file.name}", file=sys.stderr)

        try:
            view_data = load_yaml_file(view_file)
            if not view_data or not isinstance(view_data, dict):
                if args.verbose:
                    print(f"[views] Skipping {view_file.name}: empty or invalid", file=sys.stderr)
                continue
        except Exception as exc:
            print(f"Warning: could not parse {view_file.name}: {exc}", file=sys.stderr)
            continue

        parsed = parse_view(view_data, verbose=args.verbose)
        all_views.append(parsed)

    if args.verbose:
        total_displays = sum(len(v["displays"]) for v in all_views)
        print(
            f"[views] Parsed {len(all_views)} views with {total_displays} total displays",
            file=sys.stderr,
        )

    # Write output
    output_path = Path(args.output)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    with open(output_path, "w", encoding="utf-8") as f:
        json.dump(all_views, f, indent=2, ensure_ascii=False)

    if args.verbose:
        print(f"[views] Wrote {output_path}", file=sys.stderr)


if __name__ == "__main__":
    main()
