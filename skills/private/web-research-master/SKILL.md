---
name: web-research-master
description: Expert web research and internet search for up-to-date, verifiable information. Use when a user needs current facts, news, documentation, product comparisons, market trends, academic sources, or any information not in the local codebase or model memory; requires multi-source verification, citations, date checks, and bias awareness.
---

# Web Research Master

## Quick start
- Clarify the question and scope before searching.
- Form 2-4 search queries (English first; add local language variants if needed).
- Use multiple sources (3-5+ for contested topics) and prefer primary/official docs.
- Check publication dates and prefer recent sources; flag outdated info.
- Never invent. If unsure, keep searching or say what is missing.

## Core workflow
1. **Scope**: restate the question and define what counts as a correct answer.
2. **Query plan**: write a short list of targeted search queries.
3. **Source triage**: open sources, prioritize primary/official, then reputable secondary.
4. **Verify**: cross-check claims across sources; note conflicts and bias.
5. **Synthesize**: answer with a short summary, key facts, dates, and citations.
6. **Gaps**: list what could not be verified and suggest next steps.

## Quality rules
- Always include dates for time-sensitive info.
- Highlight contradictions and explain why one source may be more reliable.
- Keep quotes short and only when essential.
- Avoid suspicious links and unknown domains.
- Use the user language for the response; search primarily in English for accuracy.

## Output format
- Summary (2-4 bullets)
- Key facts with citations and dates
- Contradictions/uncertainties (if any)
- Sources list

## Resources
- `references/search-operators.md` (advanced query operators)
- `references/source-priority.md` (recommended sources by category)
- `references/query-templates.md` (templates for news, docs, comparisons)
- `scripts/build_research_report.py` (generate a report scaffold)
- `assets/Network-Access-Notes.md` (safe network access guidance)
