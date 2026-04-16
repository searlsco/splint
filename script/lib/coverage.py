#!/usr/bin/env python3
"""Coverage-floor parser used by script/test.

Parses llvm-cov lcov output and Splint source files with inline exclusion
markers, then reports the effective line-coverage percent. Accepts one
positional arg:

  --self-test   Run the in-file fixtures and exit 0/2.
  <threshold>   Float 0-100; compare effective coverage against this.
                Reads lcov on stdin.

Separated from script/test so the logic can be unit-tested without running
the full Swift suite.
"""

from __future__ import annotations

import glob
import os
import re
import sys
import tempfile
from pathlib import Path

# --- Marker regexes ---------------------------------------------------------

MARK_LINE = re.compile(r"//\s*coverage:ignore\b(?!-)(.*)")
MARK_START = re.compile(r"//\s*coverage:ignore-start\b(.*)")
MARK_END = re.compile(r"//\s*coverage:ignore-end\b")
SEP_PREFIX = re.compile(r"^[\s\-\u2014\u2013:]+")  # strip -, em-dash, en-dash, colon

MIN_RATIONALE = 10


def rationale(tail: str) -> str:
    """Return the cleaned-up rationale text after a marker's keyword."""
    return SEP_PREFIX.sub("", tail.strip()).strip()


def parse_markers(source_paths: list[str]) -> tuple[set[tuple[str, int]], list[str]]:
    """Return (excluded_line_set, errors) for the given Swift source paths.

    excluded_line_set is a set of (absolute_path, line_number) tuples.
    errors is a list of 'path:line: reason' strings.
    """
    excluded: set[tuple[str, int]] = set()
    errors: list[str] = []
    for path in source_paths:
        try:
            with open(path) as f:
                lines = f.readlines()
        except OSError as exc:
            errors.append(f"{path}: {exc}")
            continue
        block_start: int | None = None
        for lineno, text in enumerate(lines, start=1):
            if MARK_END.search(text):
                if block_start is None:
                    errors.append(f"{path}:{lineno}: stray coverage:ignore-end")
                    continue
                for j in range(block_start, lineno + 1):
                    excluded.add((os.path.abspath(path), j))
                block_start = None
                continue
            m = MARK_START.search(text)
            if m:
                if block_start is not None:
                    errors.append(
                        f"{path}:{lineno}: nested coverage:ignore-start "
                        f"(previous at line {block_start})"
                    )
                    continue
                if len(rationale(m.group(1))) < MIN_RATIONALE:
                    errors.append(
                        f"{path}:{lineno}: coverage marker missing rationale "
                        f"(>={MIN_RATIONALE} chars)"
                    )
                block_start = lineno
                continue
            m = MARK_LINE.search(text)
            if m:
                if len(rationale(m.group(1))) < MIN_RATIONALE:
                    errors.append(
                        f"{path}:{lineno}: coverage marker missing rationale "
                        f"(>={MIN_RATIONALE} chars)"
                    )
                excluded.add((os.path.abspath(path), lineno))
        if block_start is not None:
            errors.append(f"{path}:{block_start}: unclosed coverage:ignore-start")
    return excluded, errors


def parse_lcov(text: str) -> dict[str, dict[int, int]]:
    """Parse lcov DA records into {file: {line: exec_count}}.

    If a line appears in multiple DA entries, max wins — any covering
    region counts the line as covered.
    """
    file_lines: dict[str, dict[int, int]] = {}
    current: str | None = None
    for line in text.splitlines():
        if line.startswith("SF:"):
            current = line[3:]
            file_lines.setdefault(current, {})
        elif line.startswith("DA:") and current is not None:
            nr, cnt = line[3:].split(",", 1)
            ln = int(nr)
            c = int(cnt)
            file_lines[current][ln] = max(file_lines[current].get(ln, 0), c)
        elif line == "end_of_record":
            current = None
    return file_lines


def compute(
    file_lines: dict[str, dict[int, int]],
    excluded: set[tuple[str, int]],
    src_prefix: str,
) -> tuple[list[tuple[str, int, int, float, list[int]]], float]:
    """Return (per-file rows, total_pct) restricted to src_prefix files.

    Each row: (filename, eff_covered, eff_count, pct, uncovered_gap_lines).
    """
    splint_files = {f: d for f, d in file_lines.items() if f.startswith(src_prefix)}
    rows = []
    tot_count = tot_covered = 0
    for fn in sorted(splint_files):
        per_line = splint_files[fn]
        instrumented = set(per_line)
        uncov = {ln for ln, c in per_line.items() if c == 0}
        excluded_in_file = {ln for (p, ln) in excluded if p == fn} & instrumented
        ex_uncov = len(excluded_in_file & uncov)
        ex_cov = len(excluded_in_file) - ex_uncov
        eff_count = len(instrumented) - len(excluded_in_file)
        eff_covered = (len(instrumented) - len(uncov)) - ex_cov
        pct = 100.0 if eff_count == 0 else (eff_covered / eff_count * 100.0)
        gap = sorted(uncov - excluded_in_file)
        rows.append((fn, eff_covered, eff_count, pct, gap))
        tot_count += eff_count
        tot_covered += eff_covered
    total_pct = 100.0 if tot_count == 0 else (tot_covered / tot_count * 100.0)
    return rows, total_pct


# --- Self-tests -------------------------------------------------------------


def _write(tmp: str, name: str, body: str) -> str:
    path = os.path.join(tmp, name)
    with open(path, "w") as f:
        f.write(body)
    return path


def _assert(label: str, cond: bool, failures: list[str]) -> None:
    if not cond:
        failures.append(label)


def run_self_tests() -> int:
    failures: list[str] = []
    with tempfile.TemporaryDirectory() as tmp:
        # --- marker parser fixtures ---
        inline_valid = _write(
            tmp, "inline_valid.swift", "foo()  // coverage:ignore — unreachable defensive branch\n"
        )
        inline_short = _write(
            tmp, "inline_short.swift", "foo()  // coverage:ignore — x\n"
        )
        inline_empty = _write(
            tmp, "inline_empty.swift", "foo()  // coverage:ignore\n"
        )
        block_valid = _write(
            tmp,
            "block_valid.swift",
            "// coverage:ignore-start — platform API cannot be stubbed\nfoo()\nbar()\n// coverage:ignore-end\n",
        )
        block_unclosed = _write(
            tmp,
            "block_unclosed.swift",
            "// coverage:ignore-start — opens but never closes the block\nfoo()\n",
        )
        stray_end = _write(tmp, "stray_end.swift", "// coverage:ignore-end\nfoo()\n")
        block_nested = _write(
            tmp,
            "block_nested.swift",
            (
                "// coverage:ignore-start — outer block, long enough rationale\n"
                "// coverage:ignore-start — inner block, also a long enough rationale\n"
                "foo()\n"
                "// coverage:ignore-end\n"
            ),
        )
        sep_double_dash = _write(
            tmp,
            "sep_double_dash.swift",
            "foo()  // coverage:ignore -- unreachable platform quirk\n",
        )
        sep_colon = _write(
            tmp, "sep_colon.swift", "foo()  // coverage:ignore: unreachable platform quirk\n"
        )

        cases = [
            ("inline-valid", [inline_valid], {"errors_empty": True, "exclude_count": 1}),
            ("inline-short", [inline_short], {"errors_contain": "missing rationale"}),
            ("inline-empty", [inline_empty], {"errors_contain": "missing rationale"}),
            ("block-valid", [block_valid], {"errors_empty": True, "exclude_count": 4}),
            ("block-unclosed", [block_unclosed], {"errors_contain": "unclosed coverage:ignore-start"}),
            ("stray-end", [stray_end], {"errors_contain": "stray coverage:ignore-end"}),
            ("block-nested", [block_nested], {"errors_contain": "nested coverage:ignore-start"}),
            ("sep-double-dash", [sep_double_dash], {"errors_empty": True, "exclude_count": 1}),
            ("sep-colon", [sep_colon], {"errors_empty": True, "exclude_count": 1}),
        ]
        for name, paths, expect in cases:
            excluded, errors = parse_markers(paths)
            if expect.get("errors_empty"):
                _assert(
                    f"{name}: expected no errors, got {errors}",
                    not errors,
                    failures,
                )
            if "errors_contain" in expect:
                _assert(
                    f"{name}: expected error containing {expect['errors_contain']!r}, got {errors}",
                    any(expect["errors_contain"] in e for e in errors),
                    failures,
                )
            if "exclude_count" in expect:
                _assert(
                    f"{name}: expected {expect['exclude_count']} excluded lines, got {len(excluded)}",
                    len(excluded) == expect["exclude_count"],
                    failures,
                )

        # --- lcov + compute fixture ---
        # A source file with 4 lines. Lines 1-3 are inside an ignore block
        # and should be excluded from the gate. Line 4 is the "real" line.
        src_dir = os.path.join(tmp, "Sources", "Splint")
        os.makedirs(src_dir, exist_ok=True)
        real_fake = _write(
            src_dir,
            "Fake.swift",
            (
                "// coverage:ignore-start — probe block excluded from gate\n"
                "probe_uncovered_line_a()\n"
                "// coverage:ignore-end\n"
                "real_covered_line()\n"
            ),
        )

        excluded, errors = parse_markers([real_fake])
        _assert(f"fixture parse errors: {errors}", not errors, failures)
        lcov = (
            f"SF:{os.path.abspath(real_fake)}\n"
            "DA:2,0\n"  # uncovered (inside block)
            "DA:4,1\n"  # covered
            "end_of_record\n"
        )
        file_lines = parse_lcov(lcov)
        src_prefix = os.path.abspath(src_dir) + os.sep
        rows, total = compute(file_lines, excluded, src_prefix)
        _assert(
            f"compute rows wrong: {rows}",
            len(rows) == 1 and rows[0][1] == 1 and rows[0][2] == 1,
            failures,
        )
        _assert(f"compute total wrong: {total}", abs(total - 100.0) < 1e-9, failures)

        # Covered line inside an exclusion block should reduce both count
        # and covered by 1, still yielding 100% when the rest is covered.
        lcov2 = (
            f"SF:{os.path.abspath(real_fake)}\n"
            "DA:2,5\n"  # covered but excluded
            "DA:4,1\n"
            "end_of_record\n"
        )
        rows2, total2 = compute(parse_lcov(lcov2), excluded, src_prefix)
        _assert(
            f"covered-and-excluded rows wrong: {rows2}",
            len(rows2) == 1 and rows2[0][1] == 1 and rows2[0][2] == 1,
            failures,
        )
        _assert(
            f"covered-and-excluded total wrong: {total2}",
            abs(total2 - 100.0) < 1e-9,
            failures,
        )

    if failures:
        print("coverage self-test FAILED:", file=sys.stderr)
        for f in failures:
            print(f"  - {f}", file=sys.stderr)
        return 2
    print("coverage self-test OK")
    return 0


# --- CLI entry --------------------------------------------------------------


def main(argv: list[str]) -> int:
    if len(argv) != 2:
        print("usage: coverage.py --self-test | <threshold>", file=sys.stderr)
        return 2
    if argv[1] == "--self-test":
        return run_self_tests()
    threshold = float(argv[1])
    repo = Path.cwd()
    src_prefix = str(repo / "Sources" / "Splint") + os.sep

    source_files = sorted(glob.glob("Sources/Splint/**/*.swift", recursive=True))
    excluded, errors = parse_markers(source_files)
    if errors:
        print("error: coverage markers failed validation:", file=sys.stderr)
        for e in errors:
            print(f"  {e}", file=sys.stderr)
        return 2

    lcov = sys.stdin.read()
    file_lines = parse_lcov(lcov)
    rows, total_pct = compute(file_lines, excluded, src_prefix)

    print()
    print("Coverage report:")
    print(f"  {'file':<44} {'cov':>6} {'lines':>6} {'pct':>7}")
    for fn, cov, cnt, pct, _ in rows:
        rel = fn[len(str(repo)) + 1:] if fn.startswith(str(repo)) else fn
        print(f"  {rel:<44} {cov:>6} {cnt:>6} {pct:>6.2f}%")
    tot_cov = sum(r[1] for r in rows)
    tot_cnt = sum(r[2] for r in rows)
    print(f"  {'TOTAL':<44} {tot_cov:>6} {tot_cnt:>6} {total_pct:>6.2f}%")

    if total_pct + 1e-9 < threshold:
        print()
        print(f"FAIL: coverage {total_pct:.2f}% < threshold {threshold:g}%")
        print("Uncovered lines:")
        for fn, _, _, _, gap in rows:
            if gap:
                rel = fn[len(str(repo)) + 1:] if fn.startswith(str(repo)) else fn
                print(f"  {rel}: {', '.join(str(x) for x in gap)}")
        return 1

    print()
    print(f"OK: coverage {total_pct:.2f}% >= threshold {threshold:g}%")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
