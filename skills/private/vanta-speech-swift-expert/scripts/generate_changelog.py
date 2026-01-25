#!/usr/bin/env python3
"""
Generate a simple Markdown changelog from git commits.

Usage:
  generate_changelog.py [--since-ref <ref>] [--until-ref <ref>] [--since-date <date>]
                        [--max <n>] [--include-merges] [--output <path>]

Examples:
  ./generate_changelog.py --max 30
  ./generate_changelog.py --since-ref v1.2.0
  ./generate_changelog.py --since-date 2026-01-01 --output CHANGELOG.md
"""

from __future__ import annotations

import argparse
import subprocess
import sys
from typing import List, Optional


def run_git(args: List[str]) -> str:
    result = subprocess.run(
        ["git"] + args,
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    return result.stdout.strip()


def get_last_tag() -> Optional[str]:
    try:
        tag = run_git(["describe", "--tags", "--abbrev=0"])
        return tag if tag else None
    except subprocess.CalledProcessError:
        return None


def build_range(since_ref: Optional[str], until_ref: Optional[str]) -> Optional[str]:
    if since_ref and until_ref:
        return f"{since_ref}..{until_ref}"
    if since_ref:
        return f"{since_ref}..HEAD"
    if until_ref:
        return f"{until_ref}"
    return None


def build_log_args(
    git_range: Optional[str],
    since_date: Optional[str],
    max_count: int,
    include_merges: bool,
) -> List[str]:
    args: List[str] = ["log"]
    if git_range:
        args.append(git_range)
    if not include_merges:
        args.append("--no-merges")
    args.append(f"--max-count={max_count}")
    if since_date:
        args.extend(["--since", since_date])
    args.append("--pretty=format:%h %s")
    return args


def format_markdown(title: str, commits: List[str]) -> str:
    lines = [title, ""]
    if not commits:
        lines.append("- (No commits found)")
        return "\n".join(lines)
    lines.extend([f"- {c}" for c in commits])
    return "\n".join(lines)


def main() -> int:
    parser = argparse.ArgumentParser(description="Generate a Markdown changelog from git commits.")
    parser.add_argument("--since-ref", help="Git ref/tag to start from (exclusive)")
    parser.add_argument("--until-ref", help="Git ref/tag to end at (inclusive)")
    parser.add_argument("--since-date", help="Start date (passed to git --since)")
    parser.add_argument("--max", type=int, default=50, help="Max number of commits")
    parser.add_argument("--include-merges", action="store_true", help="Include merge commits")
    parser.add_argument("--output", help="Output file path (Markdown). Default: stdout")
    args = parser.parse_args()

    since_ref = args.since_ref
    if not since_ref and not args.since_date:
        since_ref = get_last_tag()

    git_range = build_range(since_ref, args.until_ref)
    log_args = build_log_args(git_range, args.since_date, args.max, args.include_merges)

    try:
        output = run_git(log_args)
    except subprocess.CalledProcessError as exc:
        sys.stderr.write(exc.stderr or "Failed to run git log.\n")
        return 1

    commits = [line.strip() for line in output.splitlines() if line.strip()]

    title_parts = ["## Changelog"]
    if since_ref:
        title_parts.append(f"(since {since_ref})")
    if args.since_date:
        title_parts.append(f"(since {args.since_date})")
    if args.until_ref:
        title_parts.append(f"(until {args.until_ref})")
    title = " ".join(title_parts)

    markdown = format_markdown(title, commits)

    if args.output:
        with open(args.output, "w", encoding="utf-8") as handle:
            handle.write(markdown + "\n")
    else:
        print(markdown)

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
