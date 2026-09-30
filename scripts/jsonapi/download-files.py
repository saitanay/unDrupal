#!/usr/bin/env python3
"""
download-files.py — Download files referenced in exported Drupal JSON:API responses.

Scans exported JSON files for file/media URLs (field_media_image, field_media_document,
uri.url fields, etc.), downloads each to a local directory preserving path structure,
deduplicates by content hash, and generates a manifest.json mapping UUIDs to local paths.

Usage:
    python download-files.py --input-dir export/ --output-dir files/
    python download-files.py --input-dir export/ --output-dir files/ --concurrency 4 --auth admin:pass
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import sys
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from typing import Any, Dict, List, Optional, Set, Tuple
from urllib.parse import urlparse, urljoin

import requests
from requests.adapters import HTTPAdapter
from urllib3.util.retry import Retry


# ---------------------------------------------------------------------------
# Session
# ---------------------------------------------------------------------------

def build_session(
    auth: Optional[Tuple[str, str]] = None,
    token: Optional[str] = None,
    retries: int = 3,
    backoff: float = 1.0,
) -> requests.Session:
    session = requests.Session()
    if auth:
        session.auth = auth
    headers: Dict[str, str] = {
        "User-Agent": "undrupal/download-files",
    }
    if token:
        headers["Authorization"] = f"Bearer {token}"
    session.headers.update(headers)

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


# ---------------------------------------------------------------------------
# File URL extraction
# ---------------------------------------------------------------------------

def extract_file_urls(
    obj: Any,
    base_url: Optional[str] = None,
    source_uuid: Optional[str] = None,
    parent_key: str = "",
) -> List[Dict[str, str]]:
    """
    Recursively walk a parsed JSON structure and extract file URLs.

    Looks for patterns common in Drupal JSON:API file/media entities:
      - attributes.uri.url  (file entities)
      - attributes.url      (file entities, some configs)
      - meta.derivatives.*  (image styles)
      - field_media_image / field_media_document relationship data with file refs
    """
    results: List[Dict[str, str]] = []

    if isinstance(obj, dict):
        # Direct URL in uri object (file--file entities)
        if "uri" in obj and isinstance(obj["uri"], dict):
            url = obj["uri"].get("url")
            if url and isinstance(url, str):
                full_url = _absolutize(url, base_url)
                results.append({
                    "url": full_url,
                    "source_uuid": source_uuid or "",
                    "field": parent_key or "uri.url",
                })

        # Top-level url attribute
        if "url" in obj and isinstance(obj["url"], str) and parent_key == "attributes":
            url = obj["url"]
            if _looks_like_file_url(url):
                full_url = _absolutize(url, base_url)
                results.append({
                    "url": full_url,
                    "source_uuid": source_uuid or "",
                    "field": "attributes.url",
                })

        # Image style derivatives
        if "derivatives" in obj and isinstance(obj["derivatives"], dict):
            for style_name, style_data in obj["derivatives"].items():
                if isinstance(style_data, dict) and "href" in style_data:
                    href = style_data["href"]
                    full_url = _absolutize(href, base_url)
                    results.append({
                        "url": full_url,
                        "source_uuid": source_uuid or "",
                        "field": f"derivatives.{style_name}",
                    })

        # Recurse into all values
        for key, value in obj.items():
            # Track the UUID of the current entity
            current_uuid = source_uuid
            if key == "id" and isinstance(value, str) and _is_uuid(value):
                pass  # don't override here, handled at entity level
            if key == "data" and isinstance(value, dict) and "id" in value:
                current_uuid = value.get("id", source_uuid)

            child_results = extract_file_urls(
                value,
                base_url=base_url,
                source_uuid=current_uuid or source_uuid,
                parent_key=key,
            )
            results.extend(child_results)

    elif isinstance(obj, list):
        for item in obj:
            child_uuid = source_uuid
            if isinstance(item, dict) and "id" in item:
                child_uuid = item.get("id", source_uuid)
            results.extend(
                extract_file_urls(item, base_url=base_url, source_uuid=child_uuid, parent_key=parent_key)
            )

    return results


def _absolutize(url: str, base_url: Optional[str]) -> str:
    """Make a URL absolute if it's relative."""
    if url.startswith(("http://", "https://")):
        return url
    if base_url:
        return urljoin(base_url.rstrip("/") + "/", url.lstrip("/"))
    return url


def _looks_like_file_url(url: str) -> bool:
    """Heuristic: does this look like a file URL rather than an API endpoint?"""
    path = urlparse(url).path.lower()
    file_extensions = {
        ".jpg", ".jpeg", ".png", ".gif", ".webp", ".svg", ".bmp", ".ico",
        ".pdf", ".doc", ".docx", ".xls", ".xlsx", ".ppt", ".pptx",
        ".mp3", ".mp4", ".wav", ".ogg", ".webm", ".avi", ".mov",
        ".zip", ".tar", ".gz", ".csv", ".txt", ".xml",
    }
    return any(path.endswith(ext) for ext in file_extensions)


def _is_uuid(s: str) -> bool:
    """Quick check for UUID-shaped string."""
    return len(s) == 36 and s.count("-") == 4


# ---------------------------------------------------------------------------
# Scanning
# ---------------------------------------------------------------------------

def scan_exported_files(
    input_dir: str,
    base_url: Optional[str] = None,
    verbose: bool = False,
) -> List[Dict[str, str]]:
    """Walk exported JSON files and collect all file URLs."""
    all_urls: List[Dict[str, str]] = []
    seen_urls: Set[str] = set()

    for root, _dirs, files in os.walk(input_dir):
        for fname in files:
            if not fname.endswith(".json") or fname.startswith("_"):
                continue
            filepath = os.path.join(root, fname)
            try:
                with open(filepath, "r", encoding="utf-8") as f:
                    doc = json.load(f)
            except (json.JSONDecodeError, OSError):
                continue

            # Derive source UUID from filename
            source_uuid = fname.replace(".json", "") if _is_uuid(fname.replace(".json", "")) else ""

            found = extract_file_urls(doc, base_url=base_url, source_uuid=source_uuid)
            for entry in found:
                url = entry["url"]
                if url not in seen_urls:
                    seen_urls.add(url)
                    all_urls.append(entry)

    if verbose:
        print(f"[download] Found {len(all_urls)} unique file URLs", file=sys.stderr)

    return all_urls


# ---------------------------------------------------------------------------
# Downloading
# ---------------------------------------------------------------------------

def download_file(
    session: requests.Session,
    url: str,
    output_dir: str,
    known_hashes: Dict[str, str],
    verbose: bool = False,
) -> Optional[Dict[str, str]]:
    """
    Download a single file. Returns manifest entry or None on failure.
    Deduplicates by SHA-256 hash.
    """
    try:
        resp = session.get(url, timeout=60, stream=True)
        if resp.status_code in (403, 404):
            if verbose:
                print(f"[download] {resp.status_code} {url} — skipping", file=sys.stderr)
            return None
        resp.raise_for_status()
    except requests.RequestException as exc:
        print(f"[download] Error fetching {url}: {exc}", file=sys.stderr)
        return None

    # Read content and hash
    content = resp.content
    file_hash = hashlib.sha256(content).hexdigest()

    # Dedup check
    if file_hash in known_hashes:
        if verbose:
            print(f"[download] Dedup: {url} -> {known_hashes[file_hash]}", file=sys.stderr)
        return {
            "url": url,
            "local_path": known_hashes[file_hash],
            "sha256": file_hash,
            "size": len(content),
            "deduplicated": True,
        }

    # Determine local path preserving URL path structure
    parsed = urlparse(url)
    url_path = parsed.path.lstrip("/")
    if not url_path:
        url_path = f"unknown/{file_hash[:12]}"

    local_path = os.path.join(output_dir, url_path)
    os.makedirs(os.path.dirname(local_path), exist_ok=True)

    with open(local_path, "wb") as f:
        f.write(content)

    known_hashes[file_hash] = local_path

    if verbose:
        print(f"[download] Saved {url} -> {local_path} ({len(content)} bytes)", file=sys.stderr)

    return {
        "url": url,
        "local_path": local_path,
        "sha256": file_hash,
        "size": len(content),
        "deduplicated": False,
    }


def download_all(
    session: requests.Session,
    file_entries: List[Dict[str, str]],
    output_dir: str,
    concurrency: int = 4,
    verbose: bool = False,
) -> List[Dict[str, Any]]:
    """Download all files with optional concurrency."""
    os.makedirs(output_dir, exist_ok=True)
    manifest: List[Dict[str, Any]] = []
    known_hashes: Dict[str, str] = {}
    total = len(file_entries)

    if concurrency <= 1:
        # Sequential
        for i, entry in enumerate(file_entries, 1):
            result = download_file(session, entry["url"], output_dir, known_hashes, verbose)
            if result:
                result["source_uuid"] = entry.get("source_uuid", "")
                result["field"] = entry.get("field", "")
                manifest.append(result)
            if i % 10 == 0 or i == total:
                print(f"[download] Progress: {i}/{total}", file=sys.stderr)
    else:
        # Parallel
        completed = 0
        with ThreadPoolExecutor(max_workers=concurrency) as executor:
            future_to_entry = {
                executor.submit(
                    download_file, session, entry["url"], output_dir, known_hashes, verbose
                ): entry
                for entry in file_entries
            }
            for future in as_completed(future_to_entry):
                entry = future_to_entry[future]
                completed += 1
                try:
                    result = future.result()
                    if result:
                        result["source_uuid"] = entry.get("source_uuid", "")
                        result["field"] = entry.get("field", "")
                        manifest.append(result)
                except Exception as exc:
                    print(f"[download] Error: {entry['url']}: {exc}", file=sys.stderr)
                if completed % 10 == 0 or completed == total:
                    print(f"[download] Progress: {completed}/{total}", file=sys.stderr)

    return manifest


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
        description="Download files referenced in exported Drupal JSON:API responses.",
    )
    parser.add_argument(
        "--input-dir",
        required=True,
        help="Directory of exported JSON:API files (from crawl-all-content.py)",
    )
    parser.add_argument(
        "--output-dir",
        default="files",
        help="Output directory for downloaded files (default: files/)",
    )
    parser.add_argument(
        "--base-url",
        default=None,
        help="Base URL to resolve relative file paths (e.g. https://example.com)",
    )
    parser.add_argument(
        "--concurrency",
        type=int,
        default=4,
        help="Number of parallel downloads (default: 4)",
    )
    parser.add_argument(
        "--auth",
        default=None,
        help="Basic auth as user:pass (for private files)",
    )
    parser.add_argument(
        "--token",
        default=None,
        help="OAuth Bearer token (for private files)",
    )
    parser.add_argument(
        "--verbose",
        action="store_true",
        help="Print debug info to stderr",
    )
    args = parser.parse_args()

    auth = parse_auth(args.auth)
    session = build_session(auth=auth, token=args.token)

    # Scan for file URLs
    print("[download] Scanning exported files for URLs...", file=sys.stderr)
    file_entries = scan_exported_files(
        args.input_dir,
        base_url=args.base_url,
        verbose=args.verbose,
    )

    if not file_entries:
        print("[download] No file URLs found.", file=sys.stderr)
        sys.exit(0)

    print(f"[download] Downloading {len(file_entries)} files...", file=sys.stderr)

    # Download
    manifest = download_all(
        session=session,
        file_entries=file_entries,
        output_dir=args.output_dir,
        concurrency=args.concurrency,
        verbose=args.verbose,
    )

    # Write manifest
    manifest_path = os.path.join(args.output_dir, "manifest.json")
    with open(manifest_path, "w", encoding="utf-8") as f:
        json.dump(manifest, f, indent=2, ensure_ascii=False)

    total_size = sum(m.get("size", 0) for m in manifest)
    deduped = sum(1 for m in manifest if m.get("deduplicated"))
    print(
        f"\n[download] Done. {len(manifest)} files downloaded "
        f"({total_size / (1024*1024):.1f} MB), {deduped} deduplicated. "
        f"Manifest: {manifest_path}",
        file=sys.stderr,
    )


if __name__ == "__main__":
    main()
