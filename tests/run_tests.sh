#!/usr/bin/env bash
# Run all golden tests (golden.tsv + golden.local.tsv if present).
# Run before AND after touching any glossary; all green is the bar for commit.
set -euo pipefail
SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASS=0; FAIL=0; SKIP=0
for tsv in "$SKILL_DIR/tests/golden.tsv" "$SKILL_DIR/tests/golden.local.tsv"; do
  [ -f "$tsv" ] || continue
  while IFS=$'\t' read -r sedfile input expected; do
    case "$sedfile" in \#*|"") continue;; esac
    if [ ! -f "$SKILL_DIR/$sedfile" ]; then
      SKIP=$((SKIP+1)); continue
    fi
    actual="$(printf '%s\n' "$input" | sed -f "$SKILL_DIR/$sedfile")"
    if [ "$actual" = "$expected" ]; then
      PASS=$((PASS+1))
    else
      FAIL=$((FAIL+1))
      echo "✗ [$sedfile]"
      echo "  input:    $input"
      echo "  expected: $expected"
      echo "  actual:   $actual"
    fi
  done < "$tsv"
done
echo "── $PASS passed, $FAIL failed, $SKIP skipped (missing sed file)"
[ "$FAIL" -eq 0 ]
