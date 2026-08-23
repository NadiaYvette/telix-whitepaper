#!/usr/bin/env bash
#
# Telix Whitepaper — build system
#
# Usage:
#   ./build.sh              build (4-pass lualatex pipeline, no clean)
#   ./build.sh clean        remove all generated files, then build
#   ./build.sh --help       show this message
#
# Prerequisites: lualatex, biber, makeindex

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

# ── environment ──────────────────────────────────────────────────

TEXINPUTS=".:src:out:src/abstract:src/intro:src/verification:src/control-plane:src/personality:src/clustering:src/memory:src/io:src/scheduling:src/filesystem:${TEXINPUTS:-}"
BIBINPUTS="./bib:${HOME}/src/bib:${BIBINPUTS:-}"
export TEXINPUTS BIBINPUTS

MAIN="src/main.ltx"
JOB="main"
OUTDIR="out"

# ── helpers ──────────────────────────────────────────────────────

say()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m!!\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31mERROR:\033[0m %s\n' "$*" >&2; exit 1; }

# Ensure OUTDIR exists (first-pass lualatex creates it, but be safe)
mkdir -p "$OUTDIR"

run_latex() {
    lualatex --shell-escape --output-directory="$OUTDIR" \
             --interaction=nonstopmode "$MAIN" || true
}

do_biber() {
    if [ -f "$OUTDIR/$JOB.bcf" ]; then
        say "biber …"
        biber --decodecharsset=full --input-directory="$OUTDIR" \
              --output-directory="$OUTDIR" "$JOB" \
            || { warn "biber failed — check for undefined citations"; }
    fi
}

do_makeindex() {
    # makeindex operates on .idx generated in OUTDIR but expects it relative to cwd
    if [ -f "$JOB.idx" ]; then
        say "makeindex …"
        makeindex -t "$OUTDIR/$JOB.ilg" -o "$OUTDIR/$JOB.ind" "$JOB.idx" \
            || warn "makeindex failed"
    fi
}

grep_warnings() {
    local log="$OUTDIR/$JOB.log"
    grep -iE 'Warning.*(undefined|multiply|rerun|Citation.*undefined)' \
         "$log" 2>/dev/null | sort -u || true
}

# ── clean ────────────────────────────────────────────────────────

do_clean() {
    say "Cleaning generated files …"
    rm -f  "$JOB.aux" "$JOB.bbl" "$JOB.bcf" "$JOB.blg" \
          "$JOB.idx" "$JOB.ilg" "$JOB.ind" "$JOB.log" "$JOB.out" \
          "$JOB.pdf" "$JOB.run.xml" "$JOB.toc" "$JOB.rubbercache"
    rm -rf "$OUTDIR"
    mkdir -p "$OUTDIR"
}

# ── 4-pass pipeline ──────────────────────────────────────────────

do_build() {
    say "Pass 1/4 — lualatex (generate .aux/.bcf) …"
    run_latex
    do_biber
    do_makeindex
    say "Pass 2/4 — lualatex (ingest .bbl) …"
    run_latex
    say "Pass 3/4 — lualatex (resolve cross-refs) …"
    run_latex
    say "Pass 4/4 — lualatex (final) …"
    run_latex
    echo
    if grep -q 'Rerun to get' "$OUTDIR/$JOB.log" 2>/dev/null; then
        warn "Document may need another pass — re-run 'build.sh'."
    fi
    say "Done — PDF at $OUTDIR/$JOB.pdf"
    grep_warnings
}

# ── dispatch ─────────────────────────────────────────────────────

case "${1:-}" in
    clean|--clean)
        do_clean
        do_build
        ;;
    --help|-h|help)
        sed -n '2,/^$/s/^# //p' "$0"
        ;;
    "")
        do_build
        ;;
    *)
        die "Unknown option '$1'.  Use --help to see usage."
        ;;
esac