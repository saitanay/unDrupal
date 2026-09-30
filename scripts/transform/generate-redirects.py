#!/usr/bin/env python3
"""
generate-redirects.py — Generate redirect rules from Drupal path aliases and redirect data.

Takes a JSON file mapping old paths to new paths and produces platform-specific
redirect rules for nginx, Apache, Netlify, Vercel, CloudFlare, or Next.js.

Input:  JSON file with old_path -> new_path mappings (from skill 20 output).
Output: Platform-specific redirect configuration file.

Usage:
    python generate-redirects.py --input redirects.json --format nginx --output redirects.conf
    python generate-redirects.py --input redirects.json --format netlify --output _redirects
    python generate-redirects.py --input redirects.json --format nextjs --output next-redirects.js --base-url https://example.com
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path
from typing import Any, Dict, List, Optional
from urllib.parse import urlparse


def load_redirects(input_path: Path) -> List[Dict[str, Any]]:
    """
    Load redirect mappings from a JSON file.

    Accepts multiple formats:
    1. Array of objects: [{"old_path": "/old", "new_path": "/new", "status": 301}, ...]
    2. Simple object mapping: {"/old": "/new", ...}
    3. Array with source/destination keys: [{"source": "/old", "destination": "/new"}, ...]
    4. Drupal redirect export: [{"redirect_source__path": "old", "redirect_redirect__uri": "internal:/new"}, ...]
    """
    with open(input_path, "r", encoding="utf-8") as f:
        data = json.load(f)

    redirects: List[Dict[str, Any]] = []

    if isinstance(data, list):
        for item in data:
            if not isinstance(item, dict):
                continue
            redirect = _parse_redirect_item(item)
            if redirect:
                redirects.append(redirect)

    elif isinstance(data, dict):
        # Check if it's a wrapper with a "redirects" or "items" key
        items = data.get("redirects", data.get("items", data.get("data", None)))
        if isinstance(items, list):
            for item in items:
                if isinstance(item, dict):
                    redirect = _parse_redirect_item(item)
                    if redirect:
                        redirects.append(redirect)
        else:
            # Simple key-value mapping
            for old_path, new_path in data.items():
                if isinstance(new_path, str):
                    redirects.append({
                        "old_path": _normalize_path(old_path),
                        "new_path": _normalize_path(new_path),
                        "status": 301,
                    })
                elif isinstance(new_path, dict):
                    redirects.append({
                        "old_path": _normalize_path(old_path),
                        "new_path": _normalize_path(
                            new_path.get("destination", new_path.get("new_path", new_path.get("url", "")))
                        ),
                        "status": new_path.get("status", new_path.get("status_code", 301)),
                    })

    return redirects


def _parse_redirect_item(item: Dict[str, Any]) -> Optional[Dict[str, Any]]:
    """Parse a single redirect item from various possible key names."""
    # Try common key patterns
    old_path = (
        item.get("old_path")
        or item.get("source")
        or item.get("from")
        or item.get("redirect_source__path")
        or item.get("source_path")
        or item.get("internal_path")
        or item.get("path")
        or ""
    )

    new_path = (
        item.get("new_path")
        or item.get("destination")
        or item.get("to")
        or item.get("redirect_redirect__uri")
        or item.get("destination_path")
        or item.get("alias")
        or item.get("url")
        or ""
    )

    if not old_path or not new_path:
        return None

    # Handle Drupal internal:/ URI scheme
    if isinstance(new_path, str):
        new_path = re.sub(r'^internal:/', '/', new_path)
        new_path = re.sub(r'^entity:node/(\d+)', r'/node/\1', new_path)

    status = item.get("status", item.get("status_code", item.get("code", 301)))
    try:
        status = int(status)
    except (ValueError, TypeError):
        status = 301

    # Only keep redirect status codes
    if status not in (301, 302, 303, 307, 308):
        status = 301

    redirect: Dict[str, Any] = {
        "old_path": _normalize_path(str(old_path)),
        "new_path": _normalize_path(str(new_path)),
        "status": status,
    }

    # Preserve query string flag
    if item.get("preserve_query", item.get("query_string")):
        redirect["preserve_query"] = True

    # Regex flag
    if item.get("regex", item.get("is_regex")):
        redirect["regex"] = True

    # Language
    langcode = item.get("langcode", item.get("language"))
    if langcode and langcode != "und":
        redirect["langcode"] = langcode

    return redirect


def _normalize_path(path: str) -> str:
    """Ensure path starts with / and has no trailing slash (except root)."""
    path = path.strip()
    if not path:
        return "/"
    # Don't modify absolute URLs
    if path.startswith(("http://", "https://")):
        return path
    if not path.startswith("/"):
        path = "/" + path
    # Remove trailing slash except for root
    if len(path) > 1 and path.endswith("/"):
        path = path.rstrip("/")
    return path


def _escape_nginx(path: str) -> str:
    """Escape special chars for nginx config."""
    # Escape spaces and semicolons
    return path.replace(" ", r"\ ").replace(";", r"\;")


def _escape_regex_nginx(path: str) -> str:
    """Escape a literal path for use in nginx regex location."""
    special = r'\.+*?[]{}()|^$'
    return ''.join(f'\\{c}' if c in special else c for c in path)


# --- Format generators ---

def generate_nginx(
    redirects: List[Dict[str, Any]],
    base_url: Optional[str] = None,
) -> str:
    """Generate nginx rewrite rules."""
    lines = [
        "# Redirect rules generated by undrupal",
        "# Add these inside your server {} block",
        "",
    ]

    # Group by status code for cleaner output
    by_status: Dict[int, List[Dict[str, Any]]] = {}
    for r in redirects:
        status = r["status"]
        by_status.setdefault(status, []).append(r)

    for status, items in sorted(by_status.items()):
        nginx_flag = "permanent" if status == 301 else "redirect"
        lines.append(f"# {status} redirects ({len(items)} rules)")

        for r in items:
            old = _escape_nginx(r["old_path"])
            new = r["new_path"]
            if base_url and not new.startswith(("http://", "https://")):
                new = base_url.rstrip("/") + new

            if r.get("regex"):
                lines.append(f"rewrite {old} {_escape_nginx(new)} {nginx_flag};")
            else:
                # Use exact location match for non-regex
                lines.append(f"location = {old} {{")
                lines.append(f"    return {status} {_escape_nginx(new)};")
                lines.append("}")

        lines.append("")

    return "\n".join(lines)


def generate_apache(
    redirects: List[Dict[str, Any]],
    base_url: Optional[str] = None,
) -> str:
    """Generate Apache .htaccess redirect rules."""
    lines = [
        "# Redirect rules generated by undrupal",
        "# Add to .htaccess or Apache config",
        "",
        "RewriteEngine On",
        "",
    ]

    for r in redirects:
        old = r["old_path"]
        new = r["new_path"]
        status = r["status"]

        if base_url and not new.startswith(("http://", "https://")):
            new = base_url.rstrip("/") + new

        # Map status codes to Apache redirect flags
        flag_map = {301: "R=301,L", 302: "R=302,L", 307: "R=307,L", 308: "R=308,L"}
        flag = flag_map.get(status, f"R={status},L")

        if r.get("regex"):
            pattern = old.lstrip("/")
            lines.append(f"RewriteRule ^{pattern}$ {new} [{flag}]")
        else:
            # Exact match
            escaped = re.escape(old.lstrip("/"))
            query_append = ",QSA" if r.get("preserve_query") else ""
            lines.append(f"RewriteRule ^{escaped}$ {new} [{flag}{query_append}]")

    lines.append("")
    return "\n".join(lines)


def generate_netlify(
    redirects: List[Dict[str, Any]],
    base_url: Optional[str] = None,
) -> str:
    """Generate Netlify _redirects file."""
    lines = [
        "# Redirect rules generated by undrupal",
        "# Save as _redirects in your publish directory",
        "",
    ]

    for r in redirects:
        old = r["old_path"]
        new = r["new_path"]
        status = r["status"]

        if base_url and not new.startswith(("http://", "https://")):
            new = base_url.rstrip("/") + new

        # Netlify format: /old /new status_code[!]
        force = "!" if status in (301, 302) else ""
        lines.append(f"{old}  {new}  {status}{force}")

    lines.append("")
    return "\n".join(lines)


def generate_vercel(
    redirects: List[Dict[str, Any]],
    base_url: Optional[str] = None,
) -> str:
    """Generate Vercel vercel.json redirects section."""
    vercel_redirects: List[Dict[str, Any]] = []

    for r in redirects:
        old = r["old_path"]
        new = r["new_path"]
        status = r["status"]

        if base_url and not new.startswith(("http://", "https://")):
            new = base_url.rstrip("/") + new

        entry: Dict[str, Any] = {
            "source": old,
            "destination": new,
            "statusCode": status,
        }

        if r.get("regex"):
            entry["has"] = [{"type": "header", "key": "x-redirect-type", "value": "regex"}]

        vercel_redirects.append(entry)

    output = {
        "redirects": vercel_redirects,
    }

    return json.dumps(output, indent=2, ensure_ascii=False)


def generate_cloudflare(
    redirects: List[Dict[str, Any]],
    base_url: Optional[str] = None,
) -> str:
    """Generate CloudFlare Pages _redirects file."""
    # CloudFlare Pages uses the same format as Netlify
    lines = [
        "# Redirect rules generated by undrupal",
        "# Save as _redirects in your output directory",
        "# CloudFlare Pages supports up to 2000 static redirects",
        "",
    ]

    for r in redirects:
        old = r["old_path"]
        new = r["new_path"]
        status = r["status"]

        if base_url and not new.startswith(("http://", "https://")):
            new = base_url.rstrip("/") + new

        lines.append(f"{old}  {new}  {status}")

    lines.append("")
    return "\n".join(lines)


def generate_nextjs(
    redirects: List[Dict[str, Any]],
    base_url: Optional[str] = None,
) -> str:
    """Generate Next.js redirects for next.config.js."""
    lines = [
        "// Redirect rules generated by undrupal",
        "// Add to your next.config.js or next.config.mjs",
        "",
        "/** @type {import('next').NextConfig} */",
        "const redirects = async () => {",
        "  return [",
    ]

    for r in redirects:
        old = r["old_path"]
        new = r["new_path"]
        status = r["status"]
        permanent = "true" if status == 301 else "false"

        # Next.js uses :path* for catch-all and :slug for segments
        # Escape special regex chars in source for Next.js matching
        source = old
        destination = new

        if base_url and not destination.startswith(("http://", "https://")):
            destination = base_url.rstrip("/") + destination

        entry_lines = [
            "    {",
            f'      source: "{source}",',
            f'      destination: "{destination}",',
            f"      permanent: {permanent},",
            "    },",
        ]
        lines.extend(entry_lines)

    lines.extend([
        "  ];",
        "};",
        "",
        "module.exports = {",
        "  redirects,",
        "};",
        "",
    ])

    return "\n".join(lines)


FORMAT_GENERATORS = {
    "nginx": generate_nginx,
    "apache": generate_apache,
    "netlify": generate_netlify,
    "vercel": generate_vercel,
    "cloudflare": generate_cloudflare,
    "nextjs": generate_nextjs,
}


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Generate platform-specific redirect rules from Drupal path data.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=(
            "Supported formats:\n"
            "  nginx       nginx rewrite rules (server block)\n"
            "  apache      Apache .htaccess RewriteRule directives\n"
            "  netlify     Netlify _redirects file\n"
            "  vercel      Vercel vercel.json redirects array\n"
            "  cloudflare  CloudFlare Pages _redirects file\n"
            "  nextjs      Next.js next.config.js redirects function\n"
            "\n"
            "Input format (JSON):\n"
            '  [{"old_path": "/old", "new_path": "/new", "status": 301}, ...]\n'
            '  or simple mapping: {"/old": "/new", ...}\n'
            "\n"
            "Examples:\n"
            "  python generate-redirects.py --input redirects.json --format nginx --output redirects.conf\n"
            "  python generate-redirects.py --input redirects.json --format netlify --output _redirects\n"
            "  python generate-redirects.py --input aliases.json --format nextjs --output next-redirects.js --base-url https://new-site.com\n"
        ),
    )
    parser.add_argument(
        "--input", required=True,
        help="Path to JSON file with redirect mappings",
    )
    parser.add_argument(
        "--format", required=True,
        choices=list(FORMAT_GENERATORS.keys()),
        help="Output format for redirect rules",
    )
    parser.add_argument(
        "--output", required=True,
        help="Path to write redirect rules",
    )
    parser.add_argument(
        "--base-url",
        help="Base URL to prepend to relative paths (e.g. https://new-site.com)",
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

    if args.verbose:
        print(f"[redirects] Reading {input_path}", file=sys.stderr)

    try:
        redirects = load_redirects(input_path)
    except json.JSONDecodeError as exc:
        print(f"Error: invalid JSON in {input_path}: {exc}", file=sys.stderr)
        sys.exit(1)

    if not redirects:
        print("Warning: no redirects found in input file", file=sys.stderr)

    if args.verbose:
        status_counts: Dict[int, int] = {}
        for r in redirects:
            s = r["status"]
            status_counts[s] = status_counts.get(s, 0) + 1
        print(f"[redirects] Loaded {len(redirects)} redirects:", file=sys.stderr)
        for s, count in sorted(status_counts.items()):
            print(f"[redirects]   {s}: {count}", file=sys.stderr)

    # Validate base-url if provided
    if args.base_url:
        parsed = urlparse(args.base_url)
        if not parsed.scheme:
            print(
                f"Warning: --base-url should include scheme (https://...): {args.base_url}",
                file=sys.stderr,
            )

    generator = FORMAT_GENERATORS[args.format]
    output = generator(redirects, base_url=args.base_url)

    output_path = Path(args.output)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    with open(output_path, "w", encoding="utf-8") as f:
        f.write(output)

    if args.verbose:
        print(f"[redirects] Wrote {args.format} rules to {output_path}", file=sys.stderr)


if __name__ == "__main__":
    main()
