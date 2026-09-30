#!/usr/bin/env python3
"""
resolve-entity-refs.py — Resolve Drupal entity reference IDs to UUIDs, names, and URLs.

Drupal exports contain raw entity_id / target_id values that are meaningless
outside the source database. This script replaces those numeric IDs with
resolved data (uuid, title, path) using a lookup table or live database.

Handles: node references, taxonomy term references, media references, user references.

Usage:
    python resolve-entity-refs.py --input export.json --output resolved.json --lookup entities.json
    python resolve-entity-refs.py --input export.json --output resolved.json --db-url mysql://user:pass@host/db
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple


# Entity types and their typical ID field patterns
ENTITY_REF_PATTERNS = {
    "node": re.compile(r"^(target_id|nid|entity_id|node_id)$", re.IGNORECASE),
    "taxonomy_term": re.compile(r"^(target_id|tid|term_id)$", re.IGNORECASE),
    "media": re.compile(r"^(target_id|mid|media_id)$", re.IGNORECASE),
    "user": re.compile(r"^(target_id|uid|user_id|author)$", re.IGNORECASE),
    "file": re.compile(r"^(target_id|fid|file_id)$", re.IGNORECASE),
}

# Known reference field name patterns
REF_FIELD_PATTERNS = {
    "node": re.compile(r"(field_.*_node|field_.*_content|field_.*_article|field_.*_page|entity_id)", re.IGNORECASE),
    "taxonomy_term": re.compile(r"(field_.*_term|field_.*_tags|field_.*_category|field_.*_tax)", re.IGNORECASE),
    "media": re.compile(r"(field_.*_media|field_.*_image|field_.*_file|field_.*_video)", re.IGNORECASE),
    "user": re.compile(r"(field_.*_user|field_.*_author|uid|revision_uid)", re.IGNORECASE),
}


def load_lookup_table(lookup_path: str) -> Dict[str, Dict[str, Dict[str, Any]]]:
    """
    Load a lookup table from a JSON file.

    Expected format:
    {
      "node": {
        "42": {"uuid": "abc-123", "title": "My Page", "path": "/my-page"},
        ...
      },
      "taxonomy_term": {
        "7": {"uuid": "def-456", "name": "News", "path": "/tags/news"},
        ...
      },
      "media": {
        "15": {"uuid": "ghi-789", "name": "hero.jpg", "url": "/files/hero.jpg"},
        ...
      },
      "user": {
        "1": {"uuid": "jkl-012", "name": "admin", "mail": "admin@example.com"},
        ...
      }
    }
    """
    path = Path(lookup_path)
    if not path.exists():
        print(f"Error: lookup file not found: {path}", file=sys.stderr)
        sys.exit(1)

    with open(path, "r", encoding="utf-8") as f:
        data = json.load(f)

    # Normalize all keys to strings
    normalized: Dict[str, Dict[str, Dict[str, Any]]] = {}
    for entity_type, entities in data.items():
        normalized[entity_type] = {}
        if isinstance(entities, dict):
            for eid, info in entities.items():
                normalized[entity_type][str(eid)] = info
        elif isinstance(entities, list):
            # Accept list format: [{"id": 42, "title": "..."}, ...]
            for item in entities:
                if isinstance(item, dict):
                    eid = item.get("id") or item.get("nid") or item.get("tid") or item.get("mid") or item.get("uid")
                    if eid is not None:
                        normalized[entity_type][str(eid)] = item

    return normalized


def load_lookup_from_db(db_url: str, verbose: bool = False) -> Dict[str, Dict[str, Dict[str, Any]]]:
    """
    Build a lookup table from a live Drupal database.

    Requires the mysql-connector-python or psycopg2 package depending on driver.
    """
    try:
        from urllib.parse import urlparse
        parsed = urlparse(db_url)
    except Exception as exc:
        print(f"Error: cannot parse database URL: {exc}", file=sys.stderr)
        sys.exit(1)

    driver = parsed.scheme.replace("mysql+pymysql", "mysql").replace("postgresql", "pgsql")
    host = parsed.hostname or "localhost"
    port = parsed.port
    user = parsed.username or "root"
    password = parsed.password or ""
    database = parsed.path.lstrip("/")

    lookup: Dict[str, Dict[str, Dict[str, Any]]] = {
        "node": {},
        "taxonomy_term": {},
        "media": {},
        "user": {},
        "file": {},
    }

    connection = None
    try:
        if driver in ("mysql", "mariadb"):
            try:
                import mysql.connector
            except ImportError:
                print(
                    "Error: mysql-connector-python is required for MySQL connections.\n"
                    "Install with: pip install mysql-connector-python",
                    file=sys.stderr,
                )
                sys.exit(1)
            conn_kwargs: Dict[str, Any] = {
                "host": host,
                "user": user,
                "password": password,
                "database": database,
            }
            if port:
                conn_kwargs["port"] = port
            connection = mysql.connector.connect(**conn_kwargs)
        elif driver in ("pgsql", "postgres", "postgresql"):
            try:
                import psycopg2
            except ImportError:
                print(
                    "Error: psycopg2 is required for PostgreSQL connections.\n"
                    "Install with: pip install psycopg2-binary",
                    file=sys.stderr,
                )
                sys.exit(1)
            conn_kwargs = {
                "host": host,
                "user": user,
                "password": password,
                "dbname": database,
            }
            if port:
                conn_kwargs["port"] = port
            connection = psycopg2.connect(**conn_kwargs)
        else:
            print(f"Error: unsupported database driver: {driver}", file=sys.stderr)
            sys.exit(1)

        cursor = connection.cursor()

        # Nodes
        if verbose:
            print("[resolve] Loading nodes from database...", file=sys.stderr)
        try:
            cursor.execute("""
                SELECT nfd.nid, nfd.uuid, nfd.title,
                       COALESCE(pa.alias, CONCAT('/node/', nfd.nid)) AS path
                FROM node_field_data nfd
                LEFT JOIN path_alias pa
                    ON pa.path = CONCAT('/node/', nfd.nid)
                    AND pa.status = 1
            """)
            for row in cursor.fetchall():
                nid, uuid, title, path = row
                lookup["node"][str(nid)] = {
                    "uuid": uuid, "title": title, "path": path,
                }
        except Exception as exc:
            if verbose:
                print(f"[resolve] Warning: could not load nodes: {exc}", file=sys.stderr)

        # Taxonomy terms
        if verbose:
            print("[resolve] Loading taxonomy terms from database...", file=sys.stderr)
        try:
            cursor.execute("""
                SELECT tfd.tid, tfd.uuid, tfd.name,
                       COALESCE(pa.alias, CONCAT('/taxonomy/term/', tfd.tid)) AS path
                FROM taxonomy_term_field_data tfd
                LEFT JOIN path_alias pa
                    ON pa.path = CONCAT('/taxonomy/term/', tfd.tid)
                    AND pa.status = 1
            """)
            for row in cursor.fetchall():
                tid, uuid, name, path = row
                lookup["taxonomy_term"][str(tid)] = {
                    "uuid": uuid, "name": name, "path": path,
                }
        except Exception as exc:
            if verbose:
                print(f"[resolve] Warning: could not load terms: {exc}", file=sys.stderr)

        # Media
        if verbose:
            print("[resolve] Loading media from database...", file=sys.stderr)
        try:
            cursor.execute("""
                SELECT mfd.mid, mfd.uuid, mfd.name,
                       fm.uri, fm.filename
                FROM media_field_data mfd
                LEFT JOIN media__field_media_image mi ON mi.entity_id = mfd.mid
                LEFT JOIN file_managed fm ON fm.fid = mi.field_media_image_target_id
            """)
            for row in cursor.fetchall():
                mid, uuid, name, uri, filename = row
                lookup["media"][str(mid)] = {
                    "uuid": uuid, "name": name,
                    "uri": uri, "filename": filename,
                }
        except Exception as exc:
            if verbose:
                print(f"[resolve] Warning: could not load media: {exc}", file=sys.stderr)

        # Users
        if verbose:
            print("[resolve] Loading users from database...", file=sys.stderr)
        try:
            cursor.execute("""
                SELECT ufd.uid, ufd.uuid, ufd.name, ufd.mail
                FROM users_field_data ufd
            """)
            for row in cursor.fetchall():
                uid, uuid, name, mail = row
                lookup["user"][str(uid)] = {
                    "uuid": uuid, "name": name, "mail": mail,
                }
        except Exception as exc:
            if verbose:
                print(f"[resolve] Warning: could not load users: {exc}", file=sys.stderr)

        # Files
        if verbose:
            print("[resolve] Loading files from database...", file=sys.stderr)
        try:
            cursor.execute("""
                SELECT fid, uuid, filename, uri, filemime
                FROM file_managed
            """)
            for row in cursor.fetchall():
                fid, uuid, filename, uri, filemime = row
                lookup["file"][str(fid)] = {
                    "uuid": uuid, "filename": filename,
                    "uri": uri, "filemime": filemime,
                }
        except Exception as exc:
            if verbose:
                print(f"[resolve] Warning: could not load files: {exc}", file=sys.stderr)

        cursor.close()
        connection.close()

    except Exception as exc:
        if connection:
            try:
                connection.close()
            except Exception:
                pass
        print(f"Error: database connection failed: {exc}", file=sys.stderr)
        sys.exit(1)

    if verbose:
        for etype, entities in lookup.items():
            print(f"[resolve] Loaded {len(entities)} {etype} records", file=sys.stderr)

    return lookup


def detect_entity_type(field_name: str, ref_data: Dict[str, Any]) -> Optional[str]:
    """Detect which entity type a reference field points to."""
    # Explicit target_type
    target_type = ref_data.get("target_type", "")
    if target_type:
        # Normalize common variations
        type_map = {
            "node": "node",
            "taxonomy_term": "taxonomy_term",
            "taxonomy": "taxonomy_term",
            "media": "media",
            "user": "user",
            "file": "file",
            "file_managed": "file",
        }
        normalized = type_map.get(target_type.lower())
        if normalized:
            return normalized

    # JSON:API type string
    jsonapi_type = ref_data.get("type", "")
    if isinstance(jsonapi_type, str) and "--" in jsonapi_type:
        prefix = jsonapi_type.split("--")[0]
        if prefix in ("node", "taxonomy_term", "media", "user", "file"):
            return prefix

    # Infer from field name patterns
    for entity_type, pattern in REF_FIELD_PATTERNS.items():
        if pattern.search(field_name):
            return entity_type

    return None


def resolve_reference(
    field_name: str,
    ref_data: Dict[str, Any],
    lookup: Dict[str, Dict[str, Dict[str, Any]]],
    verbose: bool = False,
) -> Dict[str, Any]:
    """Resolve a single entity reference using the lookup table."""
    entity_type = detect_entity_type(field_name, ref_data)
    if not entity_type:
        return ref_data

    # Find the entity ID
    target_id = (
        ref_data.get("target_id")
        or ref_data.get("id")
        or ref_data.get("nid")
        or ref_data.get("tid")
        or ref_data.get("mid")
        or ref_data.get("uid")
        or ref_data.get("fid")
    )
    if target_id is None:
        return ref_data

    target_id_str = str(target_id)
    entity_lookup = lookup.get(entity_type, {})
    resolved_data = entity_lookup.get(target_id_str)

    if resolved_data is None:
        if verbose:
            print(
                f"[resolve] Unresolved {entity_type} reference: {target_id}",
                file=sys.stderr,
            )
        result = dict(ref_data)
        result["_unresolved"] = True
        result["_entity_type"] = entity_type
        return result

    # Merge resolved data into the reference
    result = dict(ref_data)
    result.update(resolved_data)
    result["_resolved"] = True
    result["_entity_type"] = entity_type
    return result


def resolve_value(
    field_name: str,
    value: Any,
    lookup: Dict[str, Dict[str, Dict[str, Any]]],
    verbose: bool = False,
) -> Any:
    """Recursively resolve entity references in a field value."""
    if value is None:
        return None

    if isinstance(value, dict):
        # Direct entity reference
        if "target_id" in value or "target_type" in value:
            return resolve_reference(field_name, value, lookup, verbose)

        # JSON:API data wrapper
        if "data" in value:
            data = value["data"]
            resolved = dict(value)
            if isinstance(data, list):
                resolved["data"] = [
                    resolve_reference(field_name, item, lookup, verbose)
                    if isinstance(item, dict) and ("target_id" in item or "id" in item or "type" in item)
                    else resolve_value(field_name, item, lookup, verbose)
                    for item in data
                ]
            elif isinstance(data, dict) and ("target_id" in data or "id" in data or "type" in data):
                resolved["data"] = resolve_reference(field_name, data, lookup, verbose)
            return resolved

        # Recurse into nested dicts
        return {
            k: resolve_value(k, v, lookup, verbose)
            for k, v in value.items()
        }

    if isinstance(value, list):
        return [
            resolve_reference(field_name, item, lookup, verbose)
            if isinstance(item, dict) and ("target_id" in item or "target_type" in item)
            else resolve_value(field_name, item, lookup, verbose)
            for item in value
        ]

    return value


def resolve_entity(
    entity: Dict[str, Any],
    lookup: Dict[str, Dict[str, Dict[str, Any]]],
    verbose: bool = False,
) -> Dict[str, Any]:
    """Resolve all entity references in a single entity."""
    resolved: Dict[str, Any] = {}

    for field_name, field_value in entity.items():
        resolved[field_name] = resolve_value(field_name, field_value, lookup, verbose)

    return resolved


def resolve_export(
    data: Any,
    lookup: Dict[str, Dict[str, Dict[str, Any]]],
    verbose: bool = False,
) -> Any:
    """Resolve entity references in an entire export."""
    # JSON:API compound document
    if isinstance(data, dict) and "data" in data:
        result = dict(data)
        items = data["data"]
        if isinstance(items, list):
            result["data"] = [
                resolve_entity(item, lookup, verbose)
                if isinstance(item, dict) else item
                for item in items
            ]
        elif isinstance(items, dict):
            result["data"] = resolve_entity(items, lookup, verbose)
        # Also resolve included
        if "included" in data and isinstance(data["included"], list):
            result["included"] = [
                resolve_entity(item, lookup, verbose)
                if isinstance(item, dict) else item
                for item in data["included"]
            ]
        return result

    # List of entities
    if isinstance(data, list):
        return [
            resolve_entity(item, lookup, verbose)
            if isinstance(item, dict) else item
            for item in data
        ]

    # Dict of ID -> entity
    if isinstance(data, dict):
        return {
            key: resolve_entity(value, lookup, verbose)
            if isinstance(value, dict)
            else resolve_value(key, value, lookup, verbose)
            for key, value in data.items()
        }

    return data


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Resolve Drupal entity reference IDs to UUIDs, names, and URLs.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=(
            "Examples:\n"
            "  python resolve-entity-refs.py --input export.json --output resolved.json --lookup entities.json\n"
            "  python resolve-entity-refs.py --input export.json --output resolved.json --db-url mysql://user:pass@host/db\n"
        ),
    )
    parser.add_argument(
        "--input", required=True,
        help="Path to JSON export with raw entity references",
    )
    parser.add_argument(
        "--output", required=True,
        help="Path to write resolved JSON output",
    )
    lookup_group = parser.add_mutually_exclusive_group(required=True)
    lookup_group.add_argument(
        "--lookup",
        help="Path to JSON lookup file mapping entity IDs to resolved data",
    )
    lookup_group.add_argument(
        "--db-url",
        help="Database URL for live lookup (mysql://user:pass@host/db or postgresql://...)",
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

    # Load lookup table
    if args.lookup:
        if args.verbose:
            print(f"[resolve] Loading lookup table from {args.lookup}", file=sys.stderr)
        lookup = load_lookup_table(args.lookup)
    else:
        if args.verbose:
            print(f"[resolve] Connecting to database: {args.db_url}", file=sys.stderr)
        lookup = load_lookup_from_db(args.db_url, verbose=args.verbose)

    # Load input
    if args.verbose:
        print(f"[resolve] Reading {input_path}", file=sys.stderr)
    try:
        with open(input_path, "r", encoding="utf-8") as f:
            data = json.load(f)
    except json.JSONDecodeError as exc:
        print(f"Error: invalid JSON in {input_path}: {exc}", file=sys.stderr)
        sys.exit(1)

    # Resolve
    resolved = resolve_export(data, lookup, verbose=args.verbose)

    # Write output
    output_path = Path(args.output)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    with open(output_path, "w", encoding="utf-8") as f:
        json.dump(resolved, f, indent=2, ensure_ascii=False)

    if args.verbose:
        print(f"[resolve] Wrote {output_path}", file=sys.stderr)


if __name__ == "__main__":
    main()
