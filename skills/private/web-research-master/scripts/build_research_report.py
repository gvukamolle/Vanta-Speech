#!/usr/bin/env python3
"""
Build a Markdown research report scaffold from a JSON list of sources.

Input JSON format (array):
[
  {"title":"...","url":"...","date":"YYYY-MM-DD","notes":"...","type":"primary|secondary|community"}
]

Usage:
  ./build_research_report.py --topic "Topic" --input sources.json --output report.md
"""

from __future__ import annotations

import argparse
import json
from typing import List, Dict


def load_sources(path: str) -> List[Dict[str, str]]:
    with open(path, "r", encoding="utf-8") as handle:
        data = json.load(handle)
    if not isinstance(data, list):
        raise ValueError("Input JSON must be a list of source objects")
    return data


def format_sources(sources: List[Dict[str, str]]) -> str:
    if not sources:
        return "- (No sources provided)"
    lines = []
    for item in sources:
        title = item.get("title", "(untitled)")
        url = item.get("url", "")
        date = item.get("date", "")
        notes = item.get("notes", "")
        source_type = item.get("type", "")
        parts = [title]
        if date:
            parts.append(f"[{date}]")
        if source_type:
            parts.append(f"({source_type})")
        line = "- " + " ".join(parts)
        if url:
            line += f"\n  - URL: {url}"
        if notes:
            line += f"\n  - Notes: {notes}"
        lines.append(line)
    return "\n".join(lines)


def build_report(topic: str, sources: List[Dict[str, str]]) -> str:
    return "\n".join([
        f"# Research Report: {topic}",
        "",
        "## Summary",
        "- ...",
        "- ...",
        "",
        "## Key facts (with dates)",
        "- ...",
        "",
        "## Contradictions / uncertainties",
        "- ...",
        "",
        "## Sources",
        format_sources(sources),
        "",
    ])


def main() -> int:
    parser = argparse.ArgumentParser(description="Build a Markdown research report scaffold.")
    parser.add_argument("--topic", required=True, help="Topic for the report")
    parser.add_argument("--input", required=True, help="Path to JSON sources list")
    parser.add_argument("--output", help="Output markdown path; defaults to stdout")
    args = parser.parse_args()

    sources = load_sources(args.input)
    report = build_report(args.topic, sources)

    if args.output:
        with open(args.output, "w", encoding="utf-8") as handle:
            handle.write(report)
    else:
        print(report)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
