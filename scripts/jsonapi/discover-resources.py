#!/usr/bin/env python3
"""
discover-resources.py — Auto-discover all JSON:API resource types from a Drupal site.

Hits the /jsonapi endpoint to enumerate every available entity type and bundle,
then reports the item count for each resource type using pagination metadata.

Output: a JSON file (or stdout) listing resource types with counts and endpoint URLs.

Usage:
    python discover-resources.py --base-url https://example.com --output resources.json
    python discover-resources.py --base-url https://example.com --auth admin:pass --verbose
"""

from __future__ import annotations

import argparse
import json
import sys
import time
from typing import Any, Dict, List, Optional, Tuple
from urllib.parse import urljoin

import requests
from requests.adapters import HTTPAdapter
from urllib3.util.retry import Retry


def build_session(
    auth: Optional[Tuple[str, str]] = None,
    retries: int = 3,
    backoff: float = 1.0,
) -> requests.Session:
    """Build a requests session with retry logic and optional basic auth."""
    session = requests.Session()
    if auth:
        session.auth = auth
    session.headers.update({
        "Accept": "application/vnd.api+json",
        "User-Agent": "undrupal/discover-resources",
    })
    retry_strategy = Retry(
        total=retries,
        backoff_factor=backoff,
        status_forcelist=[429, 500, 502, 503, 504],
        allowed_methods=["GET"],
    )
    adapter = HTTPAdapter(max_retries=retry_strategy)
    session.mount("https://", adapter)
    session.mount("http://", adapter)
    return session


def fetch_jsonapi_index(
    session: requests.Session,
    base_url: str,
    verbose: bool = False,
) -> Dict[str, Any]:
    """Fetch the JSON:API root index at /jsonapi."""
    url = urljoin(base_url.rstrip("/") + "/", "jsonapi")
    if verbose:
        print(f"[discover] GET {url}", file=sys.stderr)
    resp = session.get(url, timeout=30)
    resp.raise_for_status()
    return resp.json()


def parse_resource_types(index_data: Dict[str, Any]) -> List[Dict[str, str]]:
    """Extract resource type names and self-links from the JSON:API index."""
    resources: List[Dict[str, str]] = []
    links = index_data.get("links", {})
    for key, link_value in links.items():
        if key == "self":
            continue
        # link_value can be a string or an object with "href"
        if isinstance(link_value, dict):
            href = link_value.get("href", "")
        else:
            href = str(link_value)
        resources.append({
            "type": key,
            "href": href,
        })
    return resources


def get_resource_count(
    session: requests.Session,
    href: str,
    verbose: bool = False,
) -> Optional[int]:
    """
    Fetch the first page of a resource type with page[limit]=1 to read the
    total count from meta, or fall back to None if unavailable.
    """
    separator = "&" if "?" in href else "?"
    url = f"{href}{separator}page[limit]=1"
    if verbose:
        print(f"[discover] GET {url}", file=sys.stderr)
    try:
        resp = session.get(url, timeout=30)
        if resp.status_code in (403, 404):
            if verbose:
                print(
                    f"[discover]   -> {resp.status_code}, skipping count",
                    file=sys.stderr,
                )
            return None
        resp.raise_for_status()
        data = resp.json()
        # Drupal JSON:API returns count in meta.count when the
        # jsonapi_resources module or core exposes it.
        count = (data.get("meta") or {}).get("count")
        if count is not None:
            return int(count)
        # Fallback: if there is no meta.count, report the length of
        # the data array (which is at most 1 here) as a hint.
        items = data.get("data")
        if isinstance(items, list):
            if len(items) == 0:
                return 0
            # We cannot know the real total; return None to signal unknown.
            return None
        return None
    except requests.RequestException as exc:
        if verbose:
            print(f"[discover]   -> error: {exc}", file=sys.stderr)
        return None


def discover(
    base_url: str,
    auth: Optional[Tuple[str, str]] = None,
    verbose: bool = False,
    delay: float = 0.1,
) -> List[Dict[str, Any]]:
    """Full discovery: enumerate types and count items for each."""
    session = build_session(auth=auth)
    index_data = fetch_jsonapi_index(session, base_url, verbose=verbose)
    resource_types = parse_resource_types(index_data)

    if verbose:
        print(
            f"[discover] Found {len(resource_types)} resource types",
            file=sys.stderr,
        )

    results: List[Dict[str, Any]] = []
    for i, rt in enumerate(resource_types, 1):
        if verbose:
            print(
                f"[discover] ({i}/{len(resource_types)}) {rt['type']}",
                file=sys.stderr,
            )
        count = get_resource_count(session, rt["href"], verbose=verbose)
        results.append({
            "type": rt["type"],
            "href": rt["href"],
            "count": count,
        })
        if delay and i < len(resource_types):
            time.sleep(delay)

    return results


def parse_auth(auth_str: Optional[str]) -> Optional[Tuple[str, str]]:
    """Parse 'user:pass' into a tuple."""
    if not auth_str:
        return None
    if ":" not in auth_str:
        print("Error: --auth must be in user:pass format", file=sys.stderr)
        sys.exit(1)
    user, password = auth_str.split(":", 1)
    return (user, password)


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Discover all JSON:API resource types on a Drupal site.",
    )
    parser.add_argument(
        "--base-url",
        required=True,
        help="Drupal site base URL (e.g. https://example.com)",
    )
    parser.add_argument(
        "--auth",
        default=None,
        help="Basic auth credentials as user:pass",
    )
    parser.add_argument(
        "--output",
        default=None,
        help="Output file path (default: stdout)",
    )
    parser.add_argument(
        "--delay",
        type=float,
        default=0.1,
        help="Delay in seconds between count requests (default: 0.1)",
    )
    parser.add_argument(
        "--verbose",
        action="store_true",
        help="Print debug info to stderr",
    )
    args = parser.parse_args()

    auth = parse_auth(args.auth)
    results = discover(
        base_url=args.base_url,
        auth=auth,
        verbose=args.verbose,
        delay=args.delay,
    )

    output_json = json.dumps(results, indent=2)
    if args.output:
        with open(args.output, "w", encoding="utf-8") as f:
            f.write(output_json + "\n")
        if args.verbose:
            print(f"[discover] Wrote {args.output}", file=sys.stderr)
    else:
        print(output_json)

    # Summary to stderr
    total_known = sum(1 for r in results if r["count"] is not None)
    total_items = sum(r["count"] for r in results if r["count"] is not None)
    print(
        f"\nDiscovered {len(results)} resource types. "
        f"{total_known} with known counts totalling {total_items} items.",
        file=sys.stderr,
    )


if __name__ == "__main__":
    main()
