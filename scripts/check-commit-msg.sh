#!/bin/bash
# Commit message rules for this repository, shared by .githooks/commit-msg
# (local) and CI (every commit in a PR):
#   - Conventional Commits subject: type(scope)!: description
#   - English: the subject must be plain ASCII
#   - no Co-Authored-By trailer, from anyone
# Usage: check-commit-msg.sh <file-with-message>
set -u
msg_file="${1:?usage: check-commit-msg.sh <message-file>}"
subject=$(grep -v '^#' "$msg_file" | head -1)

case "$subject" in
  "Merge "* ) exit 0 ;;
esac

fail() { echo "commit message rejected: $1" >&2; echo "  subject: $subject" >&2; exit 1; }

if grep -qi '^[[:space:]]*co-authored-by:' "$msg_file"; then
  fail "Co-Authored-By trailers are not allowed in this repository."
fi
printf '%s' "$subject" | grep -qE '^(feat|fix|docs|style|refactor|perf|test|build|ci|chore|revert)(\([a-z0-9._/-]+\))?!?: [^ ].*' ||
  fail "use Conventional Commits: type(scope)!: description (feat, fix, docs, refactor, test, ci, chore...)."
if printf '%s' "$subject" | LC_ALL=C grep -q '[^ -~]'; then
  fail "write the subject in English, plain ASCII (no accented characters)."
fi
exit 0
