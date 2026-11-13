#!/usr/bin/env bash
#
# mayhem/test.sh — RUN this repo's OWN functional test suite (already built by mayhem/build.sh).
# exit 0 = pass. EDIT per repo. PATCH-grade oracle: after an agent patches the source, the grader
# rebuilds (build.sh) then runs this. DELETE this file if the repo has no meaningful tests.
#
# IMPORTANT:
#  * Must assert BEHAVIOR/OUTPUT, not just exit status. The oracle has to check asserted values /
#    golden-output diffs / known-answer results — so a PATCH that "fixes" a bug by making the program
#    exit(0) (or any no-op) FAILS here. Running inputs and checking only "exit 0 / didn't crash" is
#    NOT a functional test (it's trivially reward-hackable) — use the project's real assertion suite.
#  * Do NOT build here — mayhem/build.sh already compiled the test suite (with the project's normal
#    flags). This script only RUNS the pre-built tests and reports counts. If the test runner is
#    missing, that's a build.sh bug — fail loudly rather than silently rebuilding.
#  * REQUIRED OUTPUT — a CTRF (https://ctrf.io) summary so Mayhem/the PATCH grader reads the counts:
#      - writes a CTRF JSON report to ${CTRF_REPORT:-$SRC/ctrf-report.json}, and
#      - prints a one-line `CTRF {...}` marker to stdout (same JSON, compact).
#    Only `results.summary` (with tests/passed/failed/pending/skipped/other) is required.
#    Use the emit_ctrf helper below; it computes tests = passed+failed+skipped and sets the exit
#    code (0 iff failed==0). Map your framework's output to passed/failed/skipped.
set -uo pipefail
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH
: "${MAYHEM_JOBS:=$(nproc)}"   # build parallelism; env-overridable, falls back to nproc (use -j"$MAYHEM_JOBS")
cd "$SRC"

# emit_ctrf <tool> <passed> <failed> [skipped] [pending] [other]
# Writes a CTRF report (file + stdout `CTRF {...}` marker) and returns non-zero iff failed>0.
emit_ctrf() {
  local tool="$1" passed="$2" failed="$3" skipped="${4:-0}" pending="${5:-0}" other="${6:-0}"
  local tests=$(( passed + failed + skipped + pending + other ))
  cat > "${CTRF_REPORT:-$SRC/ctrf-report.json}" <<JSON
{
  "results": {
    "tool": { "name": "$tool" },
    "summary": {
      "tests": $tests,
      "passed": $passed,
      "failed": $failed,
      "pending": $pending,
      "skipped": $skipped,
      "other": $other
    }
  }
}
JSON
  printf 'CTRF {"results":{"tool":{"name":"%s"},"summary":{"tests":%d,"passed":%d,"failed":%d,"pending":%d,"skipped":%d,"other":%d}}}\n' \
    "$tool" "$tests" "$passed" "$failed" "$pending" "$skipped" "$other"
  [ "$failed" -eq 0 ]
}

# Two upstream JUCE UnitTest suites, one runner each (mayhem/build.sh built both; each case prints
# `TEST PASS|FAIL <suite> / <case> (passes=N failures=M)`):
#  - HLAC codec (tools/hlac_tool/Source/HlacTests.cpp): encodes synthetic signals with every compressor
#    preset, decodes them again and asserts sample equality.
#  - zstd (hi_zstd/hi_zstd/ZstdUnitTests.cpp): compress/expand round trips of ValueTree, String and File
#    through zstd::ZCompressor, asserting the expanded value equals the source.
work=$(mktemp -d); trap 'rm -rf "$work"' EXIT

passed=0; failed=0
run_suite() {   # run_suite <runner> <summary-line prefix> <min cases>
  local runner="$1" marker="$2" min="$3" log="$work/$(basename "$1").log" rc p f
  [ -x "$runner" ] || { echo "missing $runner: mayhem/build.sh did not build it" >&2; exit 2; }
  (cd "$work" && timeout 1200 "$runner") > "$log" 2>&1
  rc=$?
  cat "$log"
  p=$(grep -c '^TEST PASS ' "$log")
  f=$(grep -c '^TEST FAIL ' "$log")
  # A runner that exits early, crashes, or is neutered runs no (or too few) cases: that is a failure.
  if [ "$rc" -ne 0 ] || ! grep -q "^$marker cases=[1-9]" "$log" || [ "$p" -lt "$min" ]; then
    [ "$f" -gt 0 ] || f=1
  fi
  passed=$((passed + p)); failed=$((failed + f))
}

run_suite "$SRC/mayhem/build/hlac_unit_tests" HLAC_UNIT_TESTS 5
run_suite "$SRC/mayhem/build/zstd_unit_tests" ZSTD_UNIT_TESTS 5
emit_ctrf "juce-unittest-hlac-zstd" "$passed" "$failed" 0
