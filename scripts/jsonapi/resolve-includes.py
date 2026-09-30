#!/usr/bin/env python3
"""
resolve-includes.py — Recursive include resolution for Drupal JSON:API exports.

Takes a directory of exported JSON:API responses (as produced by crawl-all-content.py)
and resolves all relationships into fully nested documents.  Handles circular
references, paragraphs, media, and deeply nested entity trees.

Output: one file per root entity with all relationships inlined, in a flat
JSON structure (no JSON:API envelope).

Usage:
    python resolve-includes.py --input-dir export/ --output-dir resolved/
    python resolve-includes.py --input-dir export/ --output-dir resolved/ --root-types node--article,node--page
"""

from __future__ import annotations

import argparse
import json
import os
import sys
from typing import Any, Dict, List, Optional, Set


# ---------------------------------------------------------------------------
# Index builder
# ---------------------------------------------------------------------------

class EntityIndex:
    """
    Maintains a UUID -> entity lookup built from all exported JSON files.
    This lets us resolve relationships across types without re-reading files.
    """

    def __init__(self) -> None:
        # key: (type, uuid) -> entity dict (JSON:API resource object)
        self._entities: Dict[str, Dict[str, Any]] = {}

    def add(self, entity: Dict[str, Any]) -> None:
        etype = entity.get("type", "")
        eid = entity.get("id", "")
        if etype and eid:
            self._entities[f"{etype}:{eid}"] = entity

    def get(self, etype: str, eid: str) -> Optional[Dict[str, Any]]:
        return self._entities.get(f"{etype}:{eid}")

    def get_by_id(self, eid: str) -> Optional[Dict[str, Any]]:
        """Fallback: find entity by UUID alone (slower, scans all)."""
        for key, entity in self._entities.items():
            if key.endswith(f":{eid}"):
                return entity
        return None

    @property
    def count(self) -> int:
        return len(self._entities)


def build_index(input_dir: str, verbose: bool = False) -> EntityIndex:
    """Walk the input directory and index every entity and included entity."""
    index = EntityIndex()
    file_count = 0

    for root, _dirs, files in os.walk(input_dir):
        for fname in files:
            if not fname.endswith(".json") or fname.startswith("_"):
                continue
            filepath = os.path.join(root, fname)
            try:
                with open(filepath, "r", encoding="utf-8") as f:
                    doc = json.load(f)
            except (json.JSONDecodeError, OSError) as exc:
                if verbose:
                    print(f"[resolve] Skip {filepath}: {exc}", file=sys.stderr)
                continue

            file_count += 1

            # Index the primary data
            data = doc.get("data")
            if isinstance(data, dict):
                index.add(data)
            elif isinstance(data, list):
                for item in data:
                    if isinstance(item, dict):
                        index.add(item)

            # Index included entities
            for inc in doc.get("included", []):
                if isinstance(inc, dict):
                    index.add(inc)

    if verbose:
        print(
            f"[resolve] Indexed {index.count} entities from {file_count} files",
            file=sys.stderr,
        )
    return index


# ---------------------------------------------------------------------------
# Flattening / resolution
# ---------------------------------------------------------------------------

def flatten_attributes(entity: Dict[str, Any]) -> Dict[str, Any]:
    """Pull JSON:API attributes into a flat dict."""
    flat: Dict[str, Any] = {
        "id": entity.get("id"),
        "type": entity.get("type"),
    }
    for key, value in entity.get("attributes", {}).items():
        flat[key] = value
    return flat


def resolve_entity(
    entity: Dict[str, Any],
    index: EntityIndex,
    visited: Set[str],
    depth: int = 0,
    max_depth: int = 20,
    verbose: bool = False,
) -> Dict[str, Any]:
    """
    Recursively resolve an entity's relationships into nested dicts.

    Handles circular references by tracking visited (type:id) keys.
    """
    etype = entity.get("type", "")
    eid = entity.get("id", "")
    visit_key = f"{etype}:{eid}"

    flat = flatten_attributes(entity)

    if depth >= max_depth:
        if verbose:
            print(
                f"[resolve] Max depth {max_depth} reached at {visit_key}",
                file=sys.stderr,
            )
        return flat

    if visit_key in visited:
        # Circular reference — return a stub
        flat["_circular_ref"] = True
        return flat

    visited.add(visit_key)

    relationships = entity.get("relationships", {})
    for rel_name, rel_data in relationships.items():
        if not isinstance(rel_data, dict):
            continue
        rel_items = rel_data.get("data")
        if rel_items is None:
            flat[rel_name] = None
            continue

        if isinstance(rel_items, dict):
            # Single relationship
            resolved = _resolve_relationship_item(
                rel_items, index, visited, depth, max_depth, verbose
            )
            flat[rel_name] = resolved
        elif isinstance(rel_items, list):
            # Multi-value relationship
            resolved_list: List[Any] = []
            for item in rel_items:
                if isinstance(item, dict):
                    resolved = _resolve_relationship_item(
                        item, index, visited, depth, max_depth, verbose
                    )
                    resolved_list.append(resolved)
            flat[rel_name] = resolved_list

    visited.discard(visit_key)
    return flat


def _resolve_relationship_item(
    rel_ref: Dict[str, Any],
    index: EntityIndex,
    visited: Set[str],
    depth: int,
    max_depth: int,
    verbose: bool,
) -> Dict[str, Any]:
    """Resolve a single relationship reference {type, id} into a nested dict."""
    ref_type = rel_ref.get("type", "")
    ref_id = rel_ref.get("id", "")

    if not ref_type or not ref_id:
        return {"_unresolved": True, **rel_ref}

    target = index.get(ref_type, ref_id)
    if target is None:
        target = index.get_by_id(ref_id)

    if target is None:
        # Entity not in our export — leave a reference stub
        return {
            "id": ref_id,
            "type": ref_type,
            "_unresolved": True,
        }

    return resolve_entity(
        target, index, visited, depth=depth + 1,
        max_depth=max_depth, verbose=verbose,
    )


# ---------------------------------------------------------------------------
# Root entity selection
# ---------------------------------------------------------------------------

def find_root_files(
    input_dir: str,
    root_types: Optional[List[str]],
) -> List[str]:
    """
    Return file paths for entities that should be treated as roots.
    If root_types is given, only include matching type directories.
    Otherwise, use everything.
    """
    paths: List[str] = []
    for entry in sorted(os.listdir(input_dir)):
        entry_path = os.path.join(input_dir, entry)
        if not os.path.isdir(entry_path):
            continue
        if entry.startswith("_"):
            continue
        if root_types and entry not in root_types:
            continue
        for fname in sorted(os.listdir(entry_path)):
            if fname.endswith(".json"):
                paths.append(os.path.join(entry_path, fname))
    return paths


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def main() -> None:
    parser = argparse.ArgumentParser(
        description="Resolve JSON:API relationships into fully nested JSON documents.",
    )
    parser.add_argument(
        "--input-dir",
        required=True,
        help="Directory of exported JSON:API files (from crawl-all-content.py)",
    )
    parser.add_argument(
        "--output-dir",
        required=True,
        help="Output directory for resolved JSON files",
    )
    parser.add_argument(
        "--root-types",
        default=None,
        help="Comma-separated list of types to treat as root entities (default: all)",
    )
    parser.add_argument(
        "--max-depth",
        type=int,
        default=20,
        help="Maximum recursion depth for relationship resolution (default: 20)",
    )
    parser.add_argument(
        "--verbose",
        action="store_true",
        help="Print debug info to stderr",
    )
    args = parser.parse_args()

    root_types: Optional[List[str]] = None
    if args.root_types:
        root_types = [t.strip() for t in args.root_types.split(",") if t.strip()]

    # Build the global entity index
    print("[resolve] Building entity index...", file=sys.stderr)
    index = build_index(args.input_dir, verbose=args.verbose)

    # Find root entity files
    root_files = find_root_files(args.input_dir, root_types)
    if not root_files:
        print("[resolve] No root entity files found.", file=sys.stderr)
        sys.exit(1)

    print(
        f"[resolve] Resolving {len(root_files)} root entities...",
        file=sys.stderr,
    )

    os.makedirs(args.output_dir, exist_ok=True)
    resolved_count = 0
    error_count = 0

    for i, filepath in enumerate(root_files, 1):
        try:
            with open(filepath, "r", encoding="utf-8") as f:
                doc = json.load(f)
        except (json.JSONDecodeError, OSError) as exc:
            print(f"[resolve] Error reading {filepath}: {exc}", file=sys.stderr)
            error_count += 1
            continue

        data = doc.get("data")
        if not isinstance(data, dict):
            continue

        etype = data.get("type", "unknown")
        eid = data.get("id", "unknown")

        resolved = resolve_entity(
            data, index, visited=set(),
            max_depth=args.max_depth, verbose=args.verbose,
        )

        # Write to output
        type_dir = os.path.join(args.output_dir, etype)
        os.makedirs(type_dir, exist_ok=True)
        out_path = os.path.join(type_dir, f"{eid}.json")
        with open(out_path, "w", encoding="utf-8") as f:
            json.dump(resolved, f, indent=2, ensure_ascii=False)
        resolved_count += 1

        if args.verbose or i % 100 == 0:
            print(
                f"[resolve] ({i}/{len(root_files)}) {etype}/{eid}",
                file=sys.stderr,
            )

    print(
        f"\n[resolve] Done. {resolved_count} entities resolved, "
        f"{error_count} errors. Output: {args.output_dir}/",
        file=sys.stderr,
    )


if __name__ == "__main__":
    main()
