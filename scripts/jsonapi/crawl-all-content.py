#!/usr/bin/env python3
"""
crawl-all-content.py — Paginate through all content types via Drupal JSON:API.

Crawls one or more JSON:API resource types, following pagination links to
export every entity.  Each entity is saved as an individual JSON file
organized as <output-dir>/<type>/<uuid>.json.

Usage:
    python crawl-all-content.py --base-url https://example.com --types node--article,node--page --output-dir export/
    python crawl-all-content.py --base-url https://example.com --types all --auth admin:pass --verbose
    python crawl-all-content.py --base-url https://example.com --types all --token eyJhbGci...
"""

from __future__ import annotations

import argparse
import json
import os
import sys
import time
from typing import Any, Dict, List, Optional, Tuple
from urllib.parse import urljoin

import requests
from requests.adapters import HTTPAdapter
from urllib3.util.retry import Retry


# ---------------------------------------------------------------------------
# Session / HTTP helpers
# ---------------------------------------------------------------------------

def build_session(
    auth: Optional[Tuple[str, str]] = None,
    token: Optional[str] = None,
    retries: int = 3,
    backoff: float = 1.0,
) -> requests.Session:
    """Build a requests session with retry logic, auth, and JSON:API headers."""
    session = requests.Session()
    if auth:
        session.auth = auth
    headers: Dict[str, str] = {
        "Accept": "application/vnd.api+json",
        "User-Agent": "undrupal/crawl-all-content",
    }
    if token:
        headers["Authorization"] = f"Bearer {token}"
    session.headers.update(headers)

    retry_strategy = Retry(
        total=retries,
        backoff_factor=backoff,
        status_forcelist=[500, 502, 504],
        allowed_methods=["GET"],
    )
    adapter = HTTPAdapter(max_retries=retry_strategy)
    session.mount("https://", adapter)
    session.mount("http://", adapter)
    return session


def fetch_json(
    session: requests.Session,
    url: str,
    verbose: bool = False,
    max_retries_429: int = 5,
) -> Optional[Dict[str, Any]]:
    """
    GET a URL and return parsed JSON.

    Handles:
      - 429 (rate-limited): back off exponentially and retry.
      - 503: same as 429.
      - 403/404: log and return None (caller decides whether to skip).
    """
    attempt = 0
    while True:
        if verbose:
            print(f"[crawl] GET {url}", file=sys.stderr)
        try:
            resp = session.get(url, timeout=60)
        except requests.ConnectionError as exc:
            print(f"[crawl] Connection error: {exc}", file=sys.stderr)
            return None
        except requests.Timeout:
            print(f"[crawl] Timeout: {url}", file=sys.stderr)
            return None

        if resp.status_code in (429, 503):
            attempt += 1
            if attempt > max_retries_429:
                print(
                    f"[crawl] Giving up after {max_retries_429} retries on {resp.status_code}: {url}",
                    file=sys.stderr,
                )
                return None
            wait = min(2 ** attempt, 120)
            retry_after = resp.headers.get("Retry-After")
            if retry_after and retry_after.isdigit():
                wait = int(retry_after)
            print(
                f"[crawl] {resp.status_code} — retrying in {wait}s (attempt {attempt})",
                file=sys.stderr,
            )
            time.sleep(wait)
            continue

        if resp.status_code in (403, 404):
            print(
                f"[crawl] {resp.status_code} {url} — skipping",
                file=sys.stderr,
            )
            return None

        try:
            resp.raise_for_status()
        except requests.HTTPError as exc:
            print(f"[crawl] HTTP error: {exc}", file=sys.stderr)
            return None

        return resp.json()


# ---------------------------------------------------------------------------
# Discovery
# ---------------------------------------------------------------------------

def discover_all_types(
    session: requests.Session,
    base_url: str,
    verbose: bool = False,
) -> Dict[str, str]:
    """Return {type_name: href} for every resource type on the site."""
    url = urljoin(base_url.rstrip("/") + "/", "jsonapi")
    data = fetch_json(session, url, verbose=verbose)
    if not data:
        print("[crawl] Could not fetch JSON:API index", file=sys.stderr)
        sys.exit(1)
    links = data.get("links", {})
    types: Dict[str, str] = {}
    for key, link_val in links.items():
        if key == "self":
            continue
        href = link_val.get("href") if isinstance(link_val, dict) else str(link_val)
        types[key] = href
    return types


# ---------------------------------------------------------------------------
# Crawl
# ---------------------------------------------------------------------------

def crawl_type(
    session: requests.Session,
    type_name: str,
    href: str,
    include: Optional[str],
    output_dir: str,
    page_limit: int = 50,
    delay: float = 0.0,
    verbose: bool = False,
) -> Dict[str, Any]:
    """
    Paginate through all entities of one resource type and save each as
    <output_dir>/<type_name>/<uuid>.json.

    Returns a summary dict with counts.
    """
    type_dir = os.path.join(output_dir, type_name)
    os.makedirs(type_dir, exist_ok=True)

    separator = "&" if "?" in href else "?"
    url: Optional[str] = f"{href}{separator}page[limit]={page_limit}"
    if include:
        url += f"&include={include}"

    saved = 0
    skipped = 0
    errors_log: List[str] = []
    page = 0

    # Try to get total from first page meta
    total: Optional[int] = None

    while url:
        page += 1
        data = fetch_json(session, url, verbose=verbose)
        if data is None:
            errors_log.append(f"Failed to fetch page {page}: {url}")
            break

        if total is None:
            meta_count = (data.get("meta") or {}).get("count")
            if meta_count is not None:
                total = int(meta_count)

        entities = data.get("data", [])
        if not isinstance(entities, list):
            # Single-entity response (shouldn't happen in collection, but be safe)
            entities = [entities]

        for entity in entities:
            uuid = entity.get("id")
            if not uuid:
                skipped += 1
                continue
            filepath = os.path.join(type_dir, f"{uuid}.json")

            # Build a mini JSON:API document per entity, preserving included
            doc: Dict[str, Any] = {"data": entity}
            included = data.get("included")
            if included:
                doc["included"] = included

            with open(filepath, "w", encoding="utf-8") as f:
                json.dump(doc, f, indent=2, ensure_ascii=False)
            saved += 1

        progress = f"{saved}"
        if total is not None:
            progress += f"/{total}"
        print(
            f"[crawl] {type_name}: page {page}, saved {progress} entities so far",
            file=sys.stderr,
        )

        # Follow next link
        next_link = (data.get("links") or {}).get("next")
        if next_link:
            url = next_link.get("href") if isinstance(next_link, dict) else str(next_link)
        else:
            url = None

        if delay and url:
            time.sleep(delay)

    return {
        "type": type_name,
        "saved": saved,
        "skipped": skipped,
        "pages": page,
        "total_reported": total,
        "errors": errors_log,
    }


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def parse_auth(auth_str: Optional[str]) -> Optional[Tuple[str, str]]:
    if not auth_str:
        return None
    if ":" not in auth_str:
        print("Error: --auth must be in user:pass format", file=sys.stderr)
        sys.exit(1)
    user, password = auth_str.split(":", 1)
    return (user, password)


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Crawl Drupal JSON:API content types and export entities as JSON files.",
    )
    parser.add_argument(
        "--base-url",
        required=True,
        help="Drupal site base URL",
    )
    parser.add_argument(
        "--types",
        default="all",
        help='Comma-separated resource types, or "all" (default: all)',
    )
    parser.add_argument(
        "--include",
        default=None,
        help="JSON:API include parameter (comma-separated relationship paths)",
    )
    parser.add_argument(
        "--output-dir",
        default="export",
        help="Output directory (default: export/)",
    )
    parser.add_argument(
        "--page-limit",
        type=int,
        default=50,
        help="Entities per page (default: 50)",
    )
    parser.add_argument(
        "--delay",
        type=float,
        default=0.0,
        help="Delay in seconds between page requests (rate limiting)",
    )
    parser.add_argument(
        "--auth",
        default=None,
        help="Basic auth as user:pass",
    )
    parser.add_argument(
        "--token",
        default=None,
        help="OAuth Bearer token",
    )
    parser.add_argument(
        "--verbose",
        action="store_true",
        help="Print debug info to stderr",
    )
    args = parser.parse_args()

    auth = parse_auth(args.auth)
    session = build_session(auth=auth, token=args.token)

    # Determine which types to crawl
    all_types = discover_all_types(session, args.base_url, verbose=args.verbose)
    if args.types.lower() == "all":
        types_to_crawl = all_types
    else:
        requested = [t.strip() for t in args.types.split(",") if t.strip()]
        types_to_crawl = {}
        for t in requested:
            if t in all_types:
                types_to_crawl[t] = all_types[t]
            else:
                print(f"[crawl] Warning: type '{t}' not found in JSON:API index", file=sys.stderr)

    if not types_to_crawl:
        print("[crawl] No resource types to crawl.", file=sys.stderr)
        sys.exit(1)

    print(
        f"[crawl] Crawling {len(types_to_crawl)} resource types into {args.output_dir}/",
        file=sys.stderr,
    )

    os.makedirs(args.output_dir, exist_ok=True)
    summaries: List[Dict[str, Any]] = []

    for type_name, href in types_to_crawl.items():
        summary = crawl_type(
            session=session,
            type_name=type_name,
            href=href,
            include=args.include,
            output_dir=args.output_dir,
            page_limit=args.page_limit,
            delay=args.delay,
            verbose=args.verbose,
        )
        summaries.append(summary)

    # Write summary
    summary_path = os.path.join(args.output_dir, "_crawl_summary.json")
    with open(summary_path, "w", encoding="utf-8") as f:
        json.dump(summaries, f, indent=2)

    total_saved = sum(s["saved"] for s in summaries)
    total_errors = sum(len(s["errors"]) for s in summaries)
    print(
        f"\n[crawl] Done. {total_saved} entities saved across {len(summaries)} types. "
        f"{total_errors} errors logged. Summary: {summary_path}",
        file=sys.stderr,
    )


if __name__ == "__main__":
    main()
