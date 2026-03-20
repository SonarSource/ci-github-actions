#!/usr/bin/env python3
"""Audit GitHub Actions version usage across an organization.

Uses GitHub Code Search API (via gh CLI) to find all references to a target
action across .github/ directories (workflows + composite actions) and reports
repos not using an allowed version.

Prerequisites: gh CLI (authenticated), Python 3.7+

Usage:
    python tools/audit-action-version.py \
        --org SonarSource \
        --action SonarSource/gh-action_cache \
        --allowed-refs v1,54a48984cf6564fd48f3c6c67c0891d7fe89604c \
        [--output report.csv] [--verbose]
"""

from __future__ import annotations

import argparse
import base64
import csv
import json
import re
import shutil
import subprocess
import sys
import time
from urllib.parse import quote
from dataclasses import dataclass


@dataclass
class ActionRef:
    repo: str
    filepath: str
    line_num: int
    current_ref: str
    compliant: bool


# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------

_verbose = False


def log(msg: str, *, is_debug: bool = False):
    """Print to stderr. Debug messages only shown if --verbose."""
    if is_debug and not _verbose:
        return
    print(msg, file=sys.stderr)


# ---------------------------------------------------------------------------
# GitHub API helper
# ---------------------------------------------------------------------------


def gh_api(endpoint: str, params: dict | None = None) -> dict:
    """Call GitHub API via gh CLI. Returns parsed JSON.

    Params are passed as URL query parameters (not form body), which is
    required for GET endpoints like /search/code.
    """
    if params:
        query_string = "&".join(
            f"{k}={quote(str(v), safe='')}" for k, v in params.items()
        )
        url = f"{endpoint}?{query_string}"
    else:
        url = endpoint
    cmd = ["gh", "api", url]
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        raise RuntimeError(f"gh api {endpoint} failed: {result.stderr.strip()}")
    return json.loads(result.stdout)


# ---------------------------------------------------------------------------
# Code Search
# ---------------------------------------------------------------------------


def _fetch_search_page(query: str, page: int) -> dict | None:
    """Fetch a single page of code search results. Returns None on failure."""
    try:
        return gh_api("search/code", {
            "q": query,
            "per_page": "100",
            "page": str(page),
        })
    except RuntimeError as e:
        log(f"Error: Search API call failed on page {page}: {e}")
        return None


def _deduplicate(items: list[dict]) -> list[dict]:
    """Deduplicate search results by repo+path."""
    seen: set[str] = set()
    unique: list[dict] = []
    for item in items:
        key = f"{item['repo']}:{item['path']}"
        if key not in seen:
            seen.add(key)
            unique.append(item)
    return unique


def search_action_usage(org: str, action: str) -> list[dict]:
    """Search for action usage across org's .github/ directories.

    Returns list of {"repo": ..., "path": ...} dicts, deduplicated.
    """
    query = f"org:{org} path:.github {action}"
    all_items: list[dict] = []
    max_pages = 10  # API cap: 1000 results = 10 pages * 100 per page

    log(f"Searching for '{action}' in .github/ across {org}...")

    for page in range(1, max_pages + 1):
        log(f"  Fetching page {page}...", is_debug=True)

        data = _fetch_search_page(query, page)
        if data is None:
            break

        items = data.get("items", [])

        if page == 1:
            log(f"Found {data.get('total_count', 0)} total matches (may include duplicates).")

        if not items:
            break

        for item in items:
            all_items.append({
                "repo": item["repository"]["full_name"],
                "path": item["path"],
            })

        if page < max_pages:
            time.sleep(6)  # Respect 10 req/min search rate limit

    if page == max_pages and data is not None and data.get("items"):
        log("Warning: Hit 1000-result API cap. Results may be incomplete.")
        log("  Consider narrowing the search or using a different approach.")

    unique = _deduplicate(all_items)
    log(f"Found {len(unique)} unique files to inspect.")
    return unique


# ---------------------------------------------------------------------------
# File content fetching + version extraction
# ---------------------------------------------------------------------------


def extract_versions_from_file(
    repo: str, filepath: str, action: str
) -> list[dict]:
    """Fetch a file and extract all action version references.

    Returns list of {"line_num": int, "ref": str} dicts.
    """
    log(f"  Fetching {repo}/{filepath}", is_debug=True)

    try:
        data = gh_api(f"repos/{repo}/contents/{filepath}")
    except RuntimeError as e:
        log(f"Warning: Could not fetch {repo}/{filepath}: {e}")
        return []

    content_b64 = data.get("content", "")
    try:
        content = base64.b64decode(content_b64).decode("utf-8")
    except Exception:
        log(f"Warning: Could not decode {repo}/{filepath}")
        return []

    # Match "uses: owner/action[/optional/subpath]@ref" with optional quotes and whitespace
    pattern = re.compile(
        rf"uses:\s*['\"]?{re.escape(action)}(/[^@\s'\"#]*)?@([^\s'\"#]+)"
    )

    results = []
    for line_num, line in enumerate(content.splitlines(), start=1):
        match = pattern.search(line)
        if match:
            results.append({"line_num": line_num, "ref": match.group(2)})

    return results


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Audit GitHub Actions version usage across an organization.",
    )
    parser.add_argument("--org", required=True, help="GitHub organization to scan")
    parser.add_argument(
        "--action",
        required=True,
        help="Action to audit (e.g. SonarSource/gh-action_cache)",
    )
    parser.add_argument(
        "--allowed-refs",
        required=True,
        help="Comma-separated list of allowed refs (tags or SHAs)",
    )
    parser.add_argument("--output", help="Output CSV file path (default: stdout)")
    parser.add_argument(
        "--verbose", action="store_true", help="Enable debug logging",
    )
    return parser.parse_args()


def check_prerequisites():
    """Verify gh CLI is available."""
    if not shutil.which("gh"):
        print("Error: 'gh' CLI is required but not installed.", file=sys.stderr)
        sys.exit(1)


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------


def main():
    global _verbose

    args = parse_args()
    _verbose = args.verbose
    check_prerequisites()

    allowed_refs = [r.strip() for r in args.allowed_refs.split(",")]

    log(f"Auditing '{args.action}' usage across org '{args.org}'...")
    log(f"Allowed refs: {', '.join(allowed_refs)}")

    # Step 1: Search for files referencing the action
    matched_files = search_action_usage(args.org, args.action)

    # Step 2: Fetch each file and extract versions
    all_refs: list[ActionRef] = []
    total_files = len(matched_files)

    log("Inspecting file contents...")

    for i, file_info in enumerate(matched_files):
        repo = file_info["repo"]
        filepath = file_info["path"]

        versions = extract_versions_from_file(repo, filepath, args.action)

        if i > 0:
            time.sleep(0.5)  # Avoid hitting GitHub secondary rate limits

        for v in versions:
            compliant = v["ref"] in allowed_refs
            all_refs.append(
                ActionRef(
                    repo=repo,
                    filepath=filepath,
                    line_num=v["line_num"],
                    current_ref=v["ref"],
                    compliant=compliant,
                )
            )

        if (i + 1) % 10 == 0:
            log(f"  Processed {i + 1}/{total_files} files...")

    log(f"Done. Processed {total_files} files.")

    # Step 3: Output CSV
    fieldnames = ["repo", "workflow_file", "line_number", "current_ref", "compliant"]

    def write_csv(writer: csv.DictWriter):
        writer.writeheader()
        for ref in all_refs:
            writer.writerow(
                {
                    "repo": ref.repo,
                    "workflow_file": ref.filepath,
                    "line_number": ref.line_num,
                    "current_ref": ref.current_ref,
                    "compliant": ref.compliant,
                }
            )

    if args.output:
        with open(args.output, "w", newline="") as f:
            write_csv(csv.DictWriter(f, fieldnames=fieldnames))
        log(f"Report written to: {args.output}")
    else:
        write_csv(csv.DictWriter(sys.stdout, fieldnames=fieldnames))

    # Step 4: Summary
    total = len(all_refs)
    non_compliant = [r for r in all_refs if not r.compliant]
    compliant_count = total - len(non_compliant)

    log("")
    log("=== Audit Summary ===")
    log(f"Total references found: {total}")
    log(f"Compliant:              {compliant_count}")
    log(f"Non-compliant:          {len(non_compliant)}")

    if non_compliant:
        log("")
        log("Non-compliant repos:")
        for ref in non_compliant:
            log(f"  - {ref.repo} {ref.filepath}:{ref.line_num} @{ref.current_ref}")
        sys.exit(1)


if __name__ == "__main__":
    main()
