#!/usr/bin/env python3
"""
Parse the four IRIS reference PDFs into structured JSON the IRIS-side
loader can consume. Run locally; the JSON files land alongside this
script and are then copied into the container by the deploy step.

Usage:
    python3 parse_reference_pdfs.py  /path/to/pdf/dir  [/output/dir]

Inputs:
    InterSystems_Glossary_of_Terms.pdf
    InterSystems_Error_Reference.pdf
    Detailed_API_Index.pdf

Outputs:
    glossary.json   — [{term, termKey, category, definition}]
    error_codes.json — [{code, message, category}]
    api_topics.json  — [{slug, title, summary, body, namespaces}]

The glossary parser keys on the recurring "Category. <text>" pattern
(category is one of System / ObjectScript / Objects / InterSystems SQL /
Java / General etc.). The error parser strips the trailing integer off
each "<message><code>" concatenated line. The API index parser groups
on the (Tools/APIs) titled pages.
"""

import json
import re
import sys
from pathlib import Path
from pypdf import PdfReader


# ---------------------------------------------------------------------------
# Glossary
# ---------------------------------------------------------------------------

# Categories that can appear at the start of a definition. The parser
# uses these to detect "term boundary": when a line ends with no period
# and the next line starts with one of these, the previous line is a
# term and the current line is the start of its definition.
KNOWN_CATEGORIES = {
    "System.", "ObjectScript.", "Objects.", "InterSystems SQL.",
    "Java.", "General.", "Productions.", "Interoperability.",
    "Health.", "FHIR.", "Mirroring.", "License.", "Security.",
    "Files.", "Locks.", "Routines.", "BPL.", "DTL.",
    "Class Compiler.", "Globals.", "Caching.", "Database.",
    "Web Services.", "ECP.", "Distributed Cache.", "Encryption.",
    "Replication.", "Indexing.", "Storage.", "Journaling.",
    "Concurrency.", "ZEN.", "Streams.", "Web Gateway.",
    "Studio.", "Management Portal.", ".NET.", "JSON.",
    "Backup.", "Logging.", "Errors.", "Documents.",
    "TSQL.", "ODBC.", "JDBC.", "REST.", "SOAP.",
    "Containers.", "Privileges.", "Auditing.", "Performance.",
    "Networking.", "Configuration.", "Routines.", "Iris.",
    "InterSystems IRIS.",
}


def parse_glossary(path: Path) -> list[dict]:
    """
    Body shape: "<term>\n<Category>. <definition lines...>\n<term>\n
    <Category>. ...". Two-pass, deterministic — collect all category-
    line indices first, then for each category line the term is the
    line directly above and the definition is everything from
    "<Category>. " through the line right before the next category's
    term.
    """
    r = PdfReader(str(path))
    raw_lines: list[str] = []
    for i in range(4, len(r.pages)):
        text = r.pages[i].extract_text() or ""
        for ln in text.split("\n"):
            ln = ln.strip()
            if not ln:
                continue
            if ln.startswith("InterSystems Glossary"):
                continue
            if re.match(r"^\d+\s*$", ln):
                continue
            if re.match(r"^Terms Beginning with ", ln):
                continue
            if re.match(r"^\d+\.\d+\s+Terms Beginning with", ln):
                continue
            raw_lines.append(ln)

    # Pass 1 — locate every category-prefixed line.
    cat_at: list[tuple[int, str]] = []
    for idx, ln in enumerate(raw_lines):
        for cat in KNOWN_CATEGORIES:
            if ln.startswith(cat + " ") or ln == cat:
                cat_at.append((idx, cat))
                break

    # Pass 2 — for each category line, the line at idx-1 is the term,
    # and the definition runs from idx through (next_cat_idx - 2). The
    # line at next_cat_idx - 1 is the NEXT entry's term, so it stops
    # at next_cat_idx - 2.
    entries: list[dict] = []
    for k, (idx, cat) in enumerate(cat_at):
        if idx == 0:
            continue
        term = raw_lines[idx - 1].strip()
        if not term or len(term) > 200:
            continue
        # First line of definition is the rest of the category line
        # after "Category. ".
        first = raw_lines[idx]
        if first == cat:
            first_def = ""
        elif first.startswith(cat + " "):
            first_def = first[len(cat) + 1 :].strip()
        else:
            first_def = first[len(cat) :].strip()
        def_lines = [first_def] if first_def else []
        next_idx = cat_at[k + 1][0] if k + 1 < len(cat_at) else len(raw_lines)
        # End of this definition is just before the next entry's term.
        end = next_idx - 1 if k + 1 < len(cat_at) else len(raw_lines)
        for j in range(idx + 1, end):
            def_lines.append(raw_lines[j])
        definition = re.sub(r"\s+", " ", " ".join(def_lines)).strip()
        if not definition:
            continue
        entries.append(
            {
                "term": term,
                "termKey": _termkey(term),
                "category": cat.rstrip("."),
                "definition": definition,
            }
        )

    # Dedup by termKey, keep first.
    seen = set()
    deduped = []
    for e in entries:
        if not e["termKey"] or e["termKey"] in seen:
            continue
        seen.add(e["termKey"])
        deduped.append(e)
    return deduped


def _termkey(term: str) -> str:
    """Canonicalize for lookup. Strips punctuation, lowercases, removes
    trailing event suffixes (ADT^A01 → adt). Keeps non-empty alnum
    sequence."""
    t = term.strip()
    # Take only the first word/token so "ADT^A01" → "ADT"
    t = re.split(r"[\^_\s,()]+", t)[0]
    t = re.sub(r"[^\w$]", "", t).lower()
    return t


# ---------------------------------------------------------------------------
# Error Reference
# ---------------------------------------------------------------------------

def parse_error_reference(path: Path) -> list[dict]:
    """
    Each table row prints as "<message><code>" on a single line because
    the column extraction concatenates them. The code is the trailing
    integer.

    Disambiguation: codes like "%15001" could split many ways
    (msg="%" code=15001, or msg="%1" code=5001, etc.). We track the
    current table's code range from the caption ("Table 1-11: General
    Error Codes - 5000 to 5199") and pick the split whose code falls
    inside that range.
    """
    r = PdfReader(str(path))
    entries: list[dict] = []
    seen_codes: set[int] = set()
    current_category = "General"
    code_lo, code_hi = None, None

    # Section heading patterns — drop these from the data stream.
    section_heading_re = re.compile(r"^\d+\.\d+\s+.*Error Codes\s+\d+\s+to\s+\d+\s*$", re.IGNORECASE)
    table_caption_re = re.compile(
        r"^Table\s+\d+[–\-]\d+:\s*(.+?)Error Codes\s*[-–]?\s*(\d+)\s*to\s*(\d+)\s*$",
        re.IGNORECASE,
    )
    # Section starts like "1.4 Error Codes 5000 to 5999" — parse the range.
    section_with_range_re = re.compile(
        r"^\d+\.\d+\s+(.*?)Error Codes\s+(\d+)\s+to\s+(\d+)\s*$",
        re.IGNORECASE,
    )
    skip_patterns = [
        re.compile(r"^InterSystems Error Reference"),
        re.compile(r"^Error Codes \d+ to \d+\s*$"),  # running header
        re.compile(r"^\d+\s*$"),
        re.compile(r"^DescriptionError Code$"),
        re.compile(r"^Error Code\s*$"),
        re.compile(r"^Description\s*$"),
    ]

    for i in range(6, len(r.pages)):
        text = r.pages[i].extract_text() or ""
        for ln in text.split("\n"):
            ln = ln.strip()
            if not ln:
                continue
            if any(p.match(ln) for p in skip_patterns):
                continue
            # Section heading w/ explicit range — sets context.
            m_sect = section_with_range_re.match(ln)
            if m_sect:
                cat = m_sect.group(1).strip().rstrip("-").strip()
                if cat:
                    current_category = cat
                code_lo, code_hi = int(m_sect.group(2)), int(m_sect.group(3))
                continue
            # Generic section heading w/o range — drop it.
            if section_heading_re.match(ln):
                continue
            # Table caption — sets context AND the active code range.
            m_tab = table_caption_re.match(ln)
            if m_tab:
                cat = m_tab.group(1).strip().rstrip("-").strip()
                if cat:
                    current_category = cat
                code_lo, code_hi = int(m_tab.group(2)), int(m_tab.group(3))
                continue
            # Table row: "<message><code>". Try splits from 5-digit
            # code down to 1-digit; pick the first whose code is in
            # the current range. Fall back to greedy when no range
            # is set.
            picked = None
            for digit_len in range(5, 0, -1):
                m_row = re.match(r"^(.*?)(\d{" + str(digit_len) + r"})$", ln)
                if not m_row:
                    continue
                msg_candidate = m_row.group(1).strip()
                try:
                    code_candidate = int(m_row.group(2))
                except ValueError:
                    continue
                if code_candidate <= 0 or code_candidate > 99999:
                    continue
                if msg_candidate == "" and digit_len > 1:
                    # Empty message likely means we ate the whole line —
                    # try a smaller code.
                    continue
                if code_lo is not None and code_hi is not None:
                    if code_lo <= code_candidate <= code_hi:
                        picked = (msg_candidate, code_candidate)
                        break
                    # Outside the range — keep trying smaller splits.
                    continue
                # No range set — accept the greedy 5-digit split.
                picked = (msg_candidate, code_candidate)
                break
            if not picked:
                continue
            msg, code = picked
            if not msg:
                continue
            if code in seen_codes:
                continue
            seen_codes.add(code)
            entries.append({
                "code": code,
                "message": msg,
                "category": current_category or "General",
            })
    return entries


# ---------------------------------------------------------------------------
# API Index
# ---------------------------------------------------------------------------

def parse_api_index(path: Path) -> list[dict]:
    """
    Each "topic" page starts with a title ending in "(Tools/APIs)" or
    similar suffix and is followed by a one-line summary, then sections.
    We treat each page (or run of pages until the next title) as a single
    record.
    """
    r = PdfReader(str(path))
    title_re = re.compile(r"^(.*?)\s*\(Tools/APIs\)\s*$")

    # Collect (page_index, lines) tuples skipping the cover/TOC.
    page_blobs: list[tuple[int, list[str]]] = []
    for i in range(4, len(r.pages)):
        text = r.pages[i].extract_text() or ""
        lns = []
        for ln in text.split("\n"):
            ln = ln.strip()
            if not ln:
                continue
            # Drop running header / footer
            if ln.startswith("Detailed API Index"):
                continue
            if re.match(r"^\d+\s*$", ln):
                continue
            lns.append(ln)
        if lns:
            page_blobs.append((i, lns))

    # Walk and split on title lines.
    records: list[dict] = []
    cur: dict | None = None
    for _, lns in page_blobs:
        for idx, ln in enumerate(lns):
            m = title_re.match(ln)
            if m:
                if cur:
                    records.append(cur)
                title = m.group(1).strip()
                cur = {
                    "slug": _slugify(title),
                    "title": title,
                    "summary": "",
                    "body": "",
                    "namespaces": "",
                }
                # Next non-empty line is the summary.
                if idx + 1 < len(lns):
                    cur["summary"] = lns[idx + 1].strip()
                continue
            if cur is None:
                continue
            # Append to body, capture Availability.
            if ln.startswith("Availability:"):
                cur["namespaces"] = ln[len("Availability:"):].strip()
            cur["body"] = (cur["body"] + " " + ln).strip()

    if cur:
        records.append(cur)

    # Dedupe by slug.
    seen = set()
    deduped = []
    for rec in records:
        if rec["slug"] in seen:
            continue
        seen.add(rec["slug"])
        # Truncate body to keep JSON manageable.
        rec["body"] = re.sub(r"\s+", " ", rec["body"])[:6000]
        rec["summary"] = re.sub(r"\s+", " ", rec["summary"])[:400]
        deduped.append(rec)
    return deduped


def _slugify(s: str) -> str:
    s = s.lower()
    s = re.sub(r"[^a-z0-9]+", "-", s)
    return s.strip("-")[:100]


# ---------------------------------------------------------------------------
# main
# ---------------------------------------------------------------------------

def main(argv: list[str]) -> int:
    if len(argv) < 2:
        print(__doc__)
        return 1
    src_dir = Path(argv[1])
    out_dir = Path(argv[2]) if len(argv) >= 3 else Path(__file__).parent
    out_dir.mkdir(parents=True, exist_ok=True)

    pairs = [
        ("glossary.json",
         parse_glossary,
         "InterSystems_Glossary_of_Terms.pdf"),
        ("error_codes.json",
         parse_error_reference,
         "InterSystems_Error_Reference.pdf"),
        ("api_topics.json",
         parse_api_index,
         "Detailed_API_Index.pdf"),
    ]

    for out_name, fn, src_name in pairs:
        src = src_dir / src_name
        if not src.exists():
            print(f"SKIP: {src} not found", file=sys.stderr)
            continue
        print(f"parsing {src} ...")
        records = fn(src)
        print(f"  → {len(records)} records")
        out = out_dir / out_name
        out.write_text(json.dumps(records, ensure_ascii=False, indent=2))
        print(f"  wrote {out}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
