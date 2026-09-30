#!/usr/bin/env python3
"""
clean-rich-text.py — Strip or convert Drupal-specific media tokens and entity references in HTML.

Drupal stores rich text as HTML containing tags and tokens that only render inside
Drupal: <drupal-media>, <drupal-entity>, [[nid:123]], data-entity-uuid attributes,
/node/42 internal paths, and D7 media JSON tokens. This script finds every
Drupal-specific pattern and converts, strips, or marks it for manual review.

Usage:
    python clean-rich-text.py --input content.json --output clean.json --lookup media.json --mode resolve
    python clean-rich-text.py --input content.json --output clean.json --mode strip
    python clean-rich-text.py --input content.json --output clean.json --mode mark --verbose
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from html import escape as html_escape
from pathlib import Path
from typing import Any, Callable, Dict, List, Match, Optional, Tuple


# --- Pattern definitions ---

# <drupal-media data-entity-type="media" data-entity-uuid="..." ...></drupal-media>
RE_DRUPAL_MEDIA = re.compile(
    r'<drupal-media\b([^>]*)>\s*</drupal-media>',
    re.DOTALL | re.IGNORECASE,
)

# <drupal-entity data-entity-type="..." data-entity-uuid="..." ...></drupal-entity>
RE_DRUPAL_ENTITY = re.compile(
    r'<drupal-entity\b([^>]*)>\s*</drupal-entity>',
    re.DOTALL | re.IGNORECASE,
)

# [[nid:123]] or [[tid:45]] tokens
RE_NID_TOKEN = re.compile(
    r'\[\[(nid|tid|mid|uid|fid):(\d+)\]\]',
)

# D7 media JSON tokens: [[{"type":"media","fid":"123",...}]]
RE_D7_MEDIA_JSON = re.compile(
    r'\[\[\s*(\{[^]]*"type"\s*:\s*"media"[^]]*\})\s*\]\]',
    re.DOTALL,
)

# data-entity-uuid attributes on any tag
RE_DATA_ENTITY_UUID = re.compile(
    r'\bdata-entity-uuid\s*=\s*"([^"]*)"',
)

# data-entity-type attributes on any tag
RE_DATA_ENTITY_TYPE = re.compile(
    r'\bdata-entity-type\s*=\s*"([^"]*)"',
)

# Internal /node/42 paths in href or src attributes
RE_INTERNAL_NODE_PATH = re.compile(
    r'((?:href|src)\s*=\s*")(/node/(\d+))([^"]*")',
    re.IGNORECASE,
)

# Internal /taxonomy/term/42 paths
RE_INTERNAL_TERM_PATH = re.compile(
    r'((?:href|src)\s*=\s*")(/taxonomy/term/(\d+))([^"]*")',
    re.IGNORECASE,
)

# Internal /user/42 paths
RE_INTERNAL_USER_PATH = re.compile(
    r'((?:href|src)\s*=\s*")(/user/(\d+))([^"]*")',
    re.IGNORECASE,
)

# Links with data-entity-uuid: <a href="/node/42" data-entity-uuid="...">
RE_LINK_WITH_UUID = re.compile(
    r'(<a\b[^>]*)\bdata-entity-uuid\s*=\s*"([^"]*)"([^>]*>)',
    re.IGNORECASE,
)


def parse_tag_attributes(attr_string: str) -> Dict[str, str]:
    """Parse HTML-style attributes from a tag's attribute string."""
    attrs: Dict[str, str] = {}
    for match in re.finditer(r'([\w-]+)\s*=\s*"([^"]*)"', attr_string):
        attrs[match.group(1).lower()] = match.group(2)
    return attrs


def lookup_by_uuid(
    uuid: str,
    lookup: Dict[str, Dict[str, str]],
) -> Optional[Dict[str, str]]:
    """Look up an entity by UUID in the lookup table."""
    return lookup.get(uuid)


def lookup_by_id(
    entity_type: str,
    entity_id: str,
    lookup: Dict[str, Dict[str, str]],
) -> Optional[Dict[str, str]]:
    """Look up an entity by type:id key in the lookup table."""
    key = f"{entity_type}:{entity_id}"
    return lookup.get(key)


def resolve_drupal_media(
    match: Match[str],
    lookup: Dict[str, Dict[str, str]],
    mode: str,
) -> str:
    """Replace a <drupal-media> tag."""
    attrs = parse_tag_attributes(match.group(1))
    uuid = attrs.get("data-entity-uuid", "")
    align = attrs.get("data-align", "")
    caption = attrs.get("data-caption", "")
    alt = attrs.get("alt", "")
    view_mode = attrs.get("data-view-mode", "full")

    if mode == "strip":
        if caption:
            return f"<!-- removed media: {caption} -->"
        return "<!-- removed drupal-media -->"

    if mode == "mark":
        return f'<!-- TODO: resolve drupal-media uuid={uuid} align={align} caption={caption} -->{match.group(0)}'

    # mode == "resolve"
    entity = lookup_by_uuid(uuid, lookup) if uuid else None

    if not entity:
        return f'<!-- unresolved drupal-media uuid={uuid} -->'

    url = entity.get("url", entity.get("uri", entity.get("path", "")))
    media_type = entity.get("type", entity.get("media_type", "image"))
    name = entity.get("name", entity.get("filename", ""))

    align_class = f' class="align-{align}"' if align else ""

    if media_type in ("image", "image_media"):
        alt_text = alt or entity.get("alt", name)
        img = f'<img src="{html_escape(url)}" alt="{html_escape(alt_text)}" />'
        if caption:
            return f'<figure{align_class}>{img}<figcaption>{caption}</figcaption></figure>'
        return f'<figure{align_class}>{img}</figure>' if align else img

    if media_type in ("document", "file"):
        return f'<a href="{html_escape(url)}" class="media-document">{html_escape(name or url)}</a>'

    if media_type in ("remote_video", "video"):
        video_url = entity.get("embed_url", url)
        tag = f'<iframe src="{html_escape(video_url)}" allowfullscreen></iframe>'
        if caption:
            return f'<figure{align_class} class="media-video">{tag}<figcaption>{caption}</figcaption></figure>'
        return f'<figure{align_class} class="media-video">{tag}</figure>'

    # Fallback
    return f'<a href="{html_escape(url)}">{html_escape(name or url)}</a>'


def resolve_drupal_entity(
    match: Match[str],
    lookup: Dict[str, Dict[str, str]],
    mode: str,
) -> str:
    """Replace a <drupal-entity> tag."""
    attrs = parse_tag_attributes(match.group(1))
    uuid = attrs.get("data-entity-uuid", "")
    entity_type = attrs.get("data-entity-type", "")

    if mode == "strip":
        return f"<!-- removed drupal-entity type={entity_type} -->"

    if mode == "mark":
        return f'<!-- TODO: resolve drupal-entity type={entity_type} uuid={uuid} -->{match.group(0)}'

    entity = lookup_by_uuid(uuid, lookup) if uuid else None
    if not entity:
        return f'<!-- unresolved drupal-entity type={entity_type} uuid={uuid} -->'

    url = entity.get("url", entity.get("uri", entity.get("path", "")))
    title = entity.get("title", entity.get("name", ""))

    if entity_type == "media":
        media_type = entity.get("type", "image")
        if media_type in ("image", "image_media"):
            alt_text = entity.get("alt", title)
            return f'<img src="{html_escape(url)}" alt="{html_escape(alt_text)}" />'
        return f'<a href="{html_escape(url)}">{html_escape(title or url)}</a>'

    return f'<a href="{html_escape(url)}">{html_escape(title or url)}</a>'


def resolve_nid_token(
    match: Match[str],
    lookup: Dict[str, Dict[str, str]],
    mode: str,
) -> str:
    """Replace [[nid:123]] style tokens."""
    entity_type_map = {
        "nid": "node", "tid": "taxonomy_term",
        "mid": "media", "uid": "user", "fid": "file",
    }
    token_type = match.group(1)
    entity_id = match.group(2)
    entity_type = entity_type_map.get(token_type, token_type)

    if mode == "strip":
        return ""

    if mode == "mark":
        return f"<!-- TODO: resolve {token_type}:{entity_id} -->{match.group(0)}"

    entity = lookup_by_id(entity_type, entity_id, lookup)
    if not entity:
        return f"<!-- unresolved {token_type}:{entity_id} -->"

    url = entity.get("url", entity.get("path", ""))
    title = entity.get("title", entity.get("name", f"{token_type}:{entity_id}"))
    return f'<a href="{html_escape(url)}">{html_escape(title)}</a>'


def resolve_d7_media_json(
    match: Match[str],
    lookup: Dict[str, Dict[str, str]],
    mode: str,
) -> str:
    """Replace D7 [[{"type":"media","fid":"123",...}]] tokens."""
    if mode == "strip":
        return "<!-- removed D7 media token -->"

    if mode == "mark":
        return f"<!-- TODO: resolve D7 media token -->{match.group(0)}"

    try:
        token_data = json.loads(match.group(1))
    except json.JSONDecodeError:
        return f"<!-- invalid D7 media JSON -->"

    fid = str(token_data.get("fid", ""))
    entity = lookup_by_id("file", fid, lookup)

    if not entity:
        return f"<!-- unresolved D7 media fid={fid} -->"

    url = entity.get("url", entity.get("uri", ""))
    alt = token_data.get("attributes", {}).get("alt", entity.get("alt", ""))
    media_type = token_data.get("view_mode", "default")

    if url.lower().endswith((".jpg", ".jpeg", ".png", ".gif", ".webp", ".svg")):
        return f'<img src="{html_escape(url)}" alt="{html_escape(alt)}" />'

    filename = entity.get("filename", entity.get("name", url))
    return f'<a href="{html_escape(url)}">{html_escape(filename)}</a>'


def resolve_internal_path(
    match: Match[str],
    entity_type: str,
    lookup: Dict[str, Dict[str, str]],
    mode: str,
) -> str:
    """Replace /node/42, /taxonomy/term/42, /user/42 paths in href/src."""
    prefix = match.group(1)    # e.g., 'href="'
    old_path = match.group(2)  # e.g., '/node/42'
    entity_id = match.group(3) # e.g., '42'
    suffix = match.group(4)    # e.g., '"'

    if mode == "strip":
        return f'{prefix}#{suffix}'

    if mode == "mark":
        return match.group(0)

    entity = lookup_by_id(entity_type, entity_id, lookup)
    if not entity:
        return match.group(0)  # leave as-is if not found

    new_path = entity.get("url", entity.get("path", old_path))
    return f'{prefix}{html_escape(new_path)}{suffix}'


def clean_data_entity_attrs(html: str, mode: str) -> str:
    """Remove or annotate data-entity-* attributes from tags."""
    if mode == "strip" or mode == "resolve":
        html = re.sub(r'\s*data-entity-uuid\s*=\s*"[^"]*"', '', html)
        html = re.sub(r'\s*data-entity-type\s*=\s*"[^"]*"', '', html)
        html = re.sub(r'\s*data-entity-embed-display\s*=\s*"[^"]*"', '', html)
        html = re.sub(r'\s*data-entity-embed-display-settings\s*=\s*"[^"]*"', '', html)
    return html


def clean_html(
    html: str,
    lookup: Dict[str, Dict[str, str]],
    mode: str = "resolve",
    verbose: bool = False,
) -> Tuple[str, Dict[str, int]]:
    """
    Clean a single HTML string of all Drupal-specific patterns.

    Returns the cleaned HTML and a dict of counts per pattern type.
    """
    counts: Dict[str, int] = {
        "drupal_media": 0,
        "drupal_entity": 0,
        "nid_token": 0,
        "d7_media_json": 0,
        "internal_node_path": 0,
        "internal_term_path": 0,
        "internal_user_path": 0,
        "data_entity_attrs": 0,
    }

    if not html or not isinstance(html, str):
        return html, counts

    # <drupal-media>
    def _replace_media(m: Match[str]) -> str:
        counts["drupal_media"] += 1
        return resolve_drupal_media(m, lookup, mode)

    html = RE_DRUPAL_MEDIA.sub(_replace_media, html)

    # <drupal-entity>
    def _replace_entity(m: Match[str]) -> str:
        counts["drupal_entity"] += 1
        return resolve_drupal_entity(m, lookup, mode)

    html = RE_DRUPAL_ENTITY.sub(_replace_entity, html)

    # D7 media JSON tokens (before nid tokens, since they also use [[ ]])
    def _replace_d7(m: Match[str]) -> str:
        counts["d7_media_json"] += 1
        return resolve_d7_media_json(m, lookup, mode)

    html = RE_D7_MEDIA_JSON.sub(_replace_d7, html)

    # [[nid:123]] tokens
    def _replace_nid(m: Match[str]) -> str:
        counts["nid_token"] += 1
        return resolve_nid_token(m, lookup, mode)

    html = RE_NID_TOKEN.sub(_replace_nid, html)

    # Internal paths: /node/42
    def _replace_node_path(m: Match[str]) -> str:
        counts["internal_node_path"] += 1
        return resolve_internal_path(m, "node", lookup, mode)

    html = RE_INTERNAL_NODE_PATH.sub(_replace_node_path, html)

    # Internal paths: /taxonomy/term/42
    def _replace_term_path(m: Match[str]) -> str:
        counts["internal_term_path"] += 1
        return resolve_internal_path(m, "taxonomy_term", lookup, mode)

    html = RE_INTERNAL_TERM_PATH.sub(_replace_term_path, html)

    # Internal paths: /user/42
    def _replace_user_path(m: Match[str]) -> str:
        counts["internal_user_path"] += 1
        return resolve_internal_path(m, "user", lookup, mode)

    html = RE_INTERNAL_USER_PATH.sub(_replace_user_path, html)

    # Clean remaining data-entity-* attributes
    attr_count = len(RE_DATA_ENTITY_UUID.findall(html))
    if attr_count > 0:
        counts["data_entity_attrs"] = attr_count
        html = clean_data_entity_attrs(html, mode)

    return html, counts


def process_value(
    value: Any,
    lookup: Dict[str, Dict[str, str]],
    mode: str,
    verbose: bool = False,
) -> Tuple[Any, Dict[str, int]]:
    """Recursively process a value, cleaning any HTML strings found."""
    total_counts: Dict[str, int] = {}

    if isinstance(value, str):
        cleaned, counts = clean_html(value, lookup, mode, verbose)
        return cleaned, counts

    if isinstance(value, list):
        result = []
        for item in value:
            processed, counts = process_value(item, lookup, mode, verbose)
            result.append(processed)
            for k, v in counts.items():
                total_counts[k] = total_counts.get(k, 0) + v
        return result, total_counts

    if isinstance(value, dict):
        result_dict: Dict[str, Any] = {}
        for k, v in value.items():
            processed, counts = process_value(v, lookup, mode, verbose)
            result_dict[k] = processed
            for ck, cv in counts.items():
                total_counts[ck] = total_counts.get(ck, 0) + cv
        return result_dict, total_counts

    return value, total_counts


def load_lookup(lookup_path: str) -> Dict[str, Dict[str, str]]:
    """
    Load the entity lookup table.

    Expected format — a flat dict keyed by UUID or type:id:
    {
      "a1b2c3d4-e5f6-...": {"url": "/files/hero.jpg", "type": "image", "alt": "Hero"},
      "node:42": {"url": "/about-us", "title": "About Us"},
      "file:15": {"url": "/files/report.pdf", "filename": "report.pdf"},
      ...
    }
    """
    path = Path(lookup_path)
    if not path.exists():
        print(f"Error: lookup file not found: {path}", file=sys.stderr)
        sys.exit(1)

    with open(path, "r", encoding="utf-8") as f:
        data = json.load(f)

    if not isinstance(data, dict):
        print(f"Error: lookup file must contain a JSON object", file=sys.stderr)
        sys.exit(1)

    return data


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Strip or convert Drupal media tokens and entity references in HTML.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=(
            "Modes:\n"
            "  resolve  Replace Drupal tokens with standard HTML using the lookup table\n"
            "  strip    Remove Drupal tokens, leaving HTML comments as placeholders\n"
            "  mark     Add TODO comments before each token for manual review\n"
            "\n"
            "Examples:\n"
            "  python clean-rich-text.py --input content.json --output clean.json --lookup media.json --mode resolve\n"
            "  python clean-rich-text.py --input content.json --output clean.json --mode strip\n"
        ),
    )
    parser.add_argument(
        "--input", required=True,
        help="Path to JSON file containing content with rich text HTML",
    )
    parser.add_argument(
        "--output", required=True,
        help="Path to write cleaned JSON output",
    )
    parser.add_argument(
        "--lookup",
        help="Path to JSON lookup file mapping UUIDs/IDs to URLs (required for resolve mode)",
    )
    parser.add_argument(
        "--mode", choices=["resolve", "strip", "mark"], default="resolve",
        help="Processing mode: resolve (default), strip, or mark",
    )
    parser.add_argument(
        "--verbose", action="store_true",
        help="Print progress and statistics to stderr",
    )
    args = parser.parse_args()

    if args.mode == "resolve" and not args.lookup:
        print("Error: --lookup is required when using --mode resolve", file=sys.stderr)
        sys.exit(1)

    # Load lookup table
    lookup: Dict[str, Dict[str, str]] = {}
    if args.lookup:
        if args.verbose:
            print(f"[clean] Loading lookup table from {args.lookup}", file=sys.stderr)
        lookup = load_lookup(args.lookup)
        if args.verbose:
            print(f"[clean] Loaded {len(lookup)} lookup entries", file=sys.stderr)

    # Load input
    input_path = Path(args.input)
    if not input_path.exists():
        print(f"Error: input file not found: {input_path}", file=sys.stderr)
        sys.exit(1)

    if args.verbose:
        print(f"[clean] Reading {input_path}", file=sys.stderr)

    try:
        with open(input_path, "r", encoding="utf-8") as f:
            data = json.load(f)
    except json.JSONDecodeError as exc:
        print(f"Error: invalid JSON in {input_path}: {exc}", file=sys.stderr)
        sys.exit(1)

    # Process
    cleaned, counts = process_value(data, lookup, args.mode, args.verbose)

    if args.verbose:
        total = sum(counts.values())
        print(f"[clean] Processed {total} Drupal-specific patterns:", file=sys.stderr)
        for pattern, count in sorted(counts.items()):
            if count > 0:
                print(f"[clean]   {pattern}: {count}", file=sys.stderr)

    # Write output
    output_path = Path(args.output)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    with open(output_path, "w", encoding="utf-8") as f:
        json.dump(cleaned, f, indent=2, ensure_ascii=False)

    if args.verbose:
        print(f"[clean] Wrote {output_path}", file=sys.stderr)


if __name__ == "__main__":
    main()
