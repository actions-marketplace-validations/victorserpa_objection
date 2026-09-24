#!/bin/bash
# Cases for skills/objection/precedents.mjs.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
P="$ROOT/skills/objection/precedents.mjs"
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
git init -q "$T/r" && cd "$T/r" || exit 1
failures=0
ok() { "$@" >/dev/null 2>&1 || { echo "FAIL (should pass): $*"; failures=$((failures + 1)); }; }
no() { "$@" >/dev/null 2>&1 && { echo "FAIL (should fail): $*"; failures=$((failures + 1)); }; }
eq() { [ "$1" = "$2" ] || { echo "FAIL: expected [$2], got [$1]"; failures=$((failures + 1)); }; }

eq "$(node "$P" list)" "(no precedents yet)"
ok node "$P" add --area apps/worker/ --pattern "temp dir not cleaned when the job fails before finally" --sha abc1234
ok node "$P" add --area "*" --pattern "constant measured on a small case reused on a large one" --sha abc1234
# Invalid input.
no node "$P" add --area "apps worker" --pattern x --sha abc1234
no node "$P" add --area a/ --pattern x --sha not-a-sha
no node "$P" add --area a/ --pattern "$(printf 'x%.0s' $(seq 161))" --sha abc1234
no node "$P" add --area apps/worker/ --pattern "Temp dir not cleaned when the job fails before finally" --sha abc1234
no node "$P" bump 9 --sha abc1234
no node "$P" bump 1
# Bump counts and moves the record sha.
ok node "$P" bump 1 --sha def5678
grep -q '^- \[2x, [0-9-]*, def5678\] apps/worker/: temp dir' .objection/precedents.md || { echo "FAIL: bump not written"; failures=$((failures + 1)); }
# Match: area prefix and "*", most repeated first.
eq "$(node "$P" match apps/worker/src/ingest.ts | head -1)" "- [2x] apps/worker/: temp dir not cleaned when the job fails before finally"
eq "$(node "$P" match apps/web/page.tsx)" "- [1x] *: constant measured on a small case reused on a large one"
# Cap: never more than 30 lines; the least repeated and oldest go first.
for i in $(seq 1 35); do node "$P" add --area "a$i/" --pattern "pattern $i" --sha abc1234 >/dev/null; done
eq "$(grep -c '^- \[' .objection/precedents.md)" "30"
grep -q 'temp dir not cleaned' .objection/precedents.md || { echo "FAIL: the 2x precedent was evicted"; failures=$((failures + 1)); }
# Match prints at most 10.
for i in $(seq 1 12); do node "$P" add --area "*" --pattern "global $i" --sha abc1234 >/dev/null; done
[ "$(node "$P" match x | wc -l | tr -d ' ')" -le 10 ] || { echo "FAIL: match printed more than 10"; failures=$((failures + 1)); }
# Hand-deleted line survives a reload; garbage lines are ignored.
printf 'garbage line\n' >>.objection/precedents.md
ok node "$P" list

if [ "$failures" = 0 ]; then echo "precedents: all cases passed"; else echo "precedents: $failures failure(s)"; exit 1; fi
