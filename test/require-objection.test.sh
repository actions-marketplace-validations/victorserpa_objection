#!/bin/bash
# Cases for require-objection.mjs and stamp.sh, including every bypass the
# hook's own two debate rounds found. Run: bash test/require-objection.test.sh
#
# Uses temporary repositories and a fake `gh` on PATH (answers
# "$STUB_SHA $STUB_BASE" to `gh pr view`), so it never talks to GitHub.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HOOK="$ROOT/plugins/objection/hooks/require-objection.mjs"
STAMP="$ROOT/plugins/objection/skills/objection/stamp.sh"
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT

gitc() { git -c user.email=t@t -c user.name=t "$@"; }
optin() { mkdir -p "$1/.claude" && printf '{"bases":["develop","master"],"defaultBase":"master"}\n' >"$1/.claude/objection.json"; }

git init -q "$T/ok" && optin "$T/ok" && gitc -C "$T/ok" add . && gitc -C "$T/ok" commit -q -m a
git init -q "$T/no" && optin "$T/no" && gitc -C "$T/no" add . && gitc -C "$T/no" commit -q -m b
git init -q "$T/off" && gitc -C "$T/off" commit -q --allow-empty -m c
OK_SHA=$(git -C "$T/ok" rev-parse HEAD)
mkdir -p "$T/ok/.git/objection"
stamp="<!-- objection: sha=$OK_SHA base=origin/develop -->"
printf '%s\n# x\nVERDICT: APPROVED\n' "$stamp" >"$T/ok/.git/objection/$OK_SHA.md"

mkdir "$T/bin"
cat >"$T/bin/gh" <<'EOF'
#!/bin/bash
[ "$1 $2" = "pr view" ] && { [ -n "${STUB_SLEEP:-}" ] && sleep "$STUB_SLEEP"; echo "$STUB_SHA ${STUB_BASE:-develop}"; exit 0; }
exit 1
EOF
chmod +x "$T/bin/gh"
export PATH="$T/bin:$PATH"

failures=0
check() { # expected cwd tool command
  local expected=$1 cwd=$2 tool=$3 cmd=$4 json rc
  json=$(node -e 'console.log(JSON.stringify({cwd:process.argv[1],tool_name:process.argv[2],tool_input:{command:process.argv[3]}}))' "$cwd" "$tool" "$cmd")
  printf '%s' "$json" | node "$HOOK" >/dev/null 2>&1
  rc=$?
  if [ "$rc" != "$expected" ]; then
    echo "FAIL (expected $expected, got $rc): [$tool] $cmd"
    failures=$((failures + 1))
  fi
}
O="$T/ok"; N="$T/no"; F="$T/off"

# Repository without .claude/objection.json: nothing is enforced.
check 0 $F Bash 'gh pr create --fill'
check 0 $F Bash 'gh pr merge 5 --auto'
check 0 $F mcp__github__create_pull_request ''

# Not about a PR: allowed.
check 0 $N Bash 'git status'
check 0 $N Bash 'gh pr list'
check 0 $N Bash 'gh pr view 12'
check 0 $N Bash 'grep -nE "gh pr create|gh pr merge" hooks/x'
check 0 $N Bash 'echo "step: git push; gh pr create"'
check 0 $N Bash 'git commit -m "docs: run cd x && gh pr merge later"'
check 0 $N Bash "git commit -F - <<'EOF'
fix: something

gh pr merge not now
EOF"
check 0 $N Bash 'gh api repos/o/r/pulls'
check 0 $N Bash 'gh api repos/o/r/pulls -F per_page=100 --method GET'
check 0 $N Bash 'gh api repos/o/r/pulls/12/comments -f body=hi'
check 0 $N Bash 'gh api repos/o/r/pulls --jq ".[].number" | jq -r . && echo -f x'
check 0 $N mcp__github__get_pull_request ''

# No record: blocked, however it is called.
check 2 $N Bash 'gh pr create --fill'
check 2 $N Bash 'gh pr new --fill'
check 2 $N Bash 'gh -R o/r pr create --fill'
check 2 $N Bash 'gh --repo=o/r pr create'
check 2 $N Bash 'x=$(gh pr create --fill)'
check 2 $N Bash 'x="$(gh pr create --fill)"'
check 2 $N Bash "(cd $N && gh pr create)"
check 2 $N Bash 'if true; then gh pr create; fi'
check 2 $N Bash 'time gh pr create'
check 2 $N Bash 'command gh pr create'
check 2 $N Bash '/opt/homebrew/bin/gh pr create'
check 2 $N Bash 'GH_REPO=o/r gh pr create'
check 2 $N Bash "bash -c 'gh pr create'"
check 2 $N Bash 'rtk gh pr ready'
check 2 $N Bash "gh pr create --body \"\$(cat <<'EOF'
body
EOF
)\""
check 2 $O Bash "git status; cd $N && gh pr create"
check 2 $O Bash "cd '$N' && gh pr create"
check 2 $N Bash 'gh api repos/o/r/pulls -f title=x -f head=a'
check 2 $N Bash "gh api 'repos/o/r/pulls' --method POST --input x.json"
check 2 $N Bash 'gh api -X PUT repos/o/r/pulls/12/merge'
check 2 $N Bash 'gh api graphql -f query="mutation{mergePullRequest(input:{}){clientMutationId}}"'
check 2 $N mcp__plugin_engineering_github__create_pull_request ''
check 2 $N mcp__plugin_engineering_github__merge_pull_request ''
check 2 $N mcp__plugin_engineering_github__update_pull_request ''
check 2 $N mcp__ccd_pr__set_auto_merge ''

# APPROVED record for the right SHA and base: allowed.
check 0 $O Bash 'gh pr create --fill --base develop'
check 0 $N Bash "cd $O && gh pr create --base develop"
check 0 $N Bash "cd '$O' && gh pr create -B develop"
# A record debated against develop does not release a PR to master
# (defaultBase in the config is master).
check 2 $O Bash 'gh pr create --fill'
check 2 $O Bash 'gh pr create --fill --base master'
export STUB_SHA=$OK_SHA
check 0 $O Bash 'gh pr merge 5 --squash'
check 0 $O Bash 'gh pr merge -R o/r 5 --squash'
check 0 $O Bash 'gh pr merge --subject "a b" 5'
check 0 $O Bash 'gh pr ready 12'
check 2 $O Bash 'gh pr merge 5 --auto --squash'
export STUB_SHA=deadbeef
check 2 $O Bash 'gh pr merge 5 --squash'
check 2 $O Bash 'gh pr ready 12'
export STUB_SHA=$OK_SHA STUB_BASE=master
check 2 $O Bash 'gh pr merge 5 --squash'
export STUB_BASE=develop

# --- Second debate round (accusation with defender) ----------------------
export STUB_SHA=deadbeef
# Multi-line GraphQL and queries read from a file.
check 2 $N Bash "gh api graphql -f query='
mutation {
  mergePullRequest(input:{pullRequestId:\"x\"}){clientMutationId}
}'"
check 2 $N Bash 'gh api graphql -F query=@m.graphql'
check 0 $N Bash 'gh api graphql -f query="query{viewer{login}}"'
# Hung gh: the hook blocks before the harness limit (internal timeout).
export STUB_SLEEP=20
start=$(date +%s)
check 2 $O Bash 'gh pr merge 5 --squash'
[ $(( $(date +%s) - start )) -lt 25 ] || { echo "FAIL: hook took over 25 s with a hung gh"; failures=$((failures + 1)); }
unset STUB_SLEEP
# -R/--repo after `pr`.
check 2 $N Bash 'gh pr -R o/r create --fill'
check 2 $N Bash 'gh pr --repo o/r merge 5'
# A shell reading stdin.
check 2 $N Bash "bash <<'EOF'
gh pr create --fill
EOF"
check 2 $N Bash "echo 'gh pr create --fill' | bash"
# Disguised names and a path in gh api.
check 2 $N Bash '\gh pr create'
check 2 $N Bash 'g\h pr create'
check 2 $N Bash '"gh" pr create'
check 2 $N Bash '/opt/homebrew/bin/gh api -X PUT repos/o/r/pulls/12/merge'
# Ambiguous directory: blocked even when the cwd has a record.
check 2 $O Bash "(cd $N); gh pr create --base develop"
check 2 $O Bash "pushd $N; gh pr create --base develop"
check 2 $O Bash "env -C $N gh pr create --base develop"
check 2 $O Bash "echo \"a cd $O b\"; cd $N && gh pr create --base develop"
check 0 $N Bash "(cd $O && gh pr create --base develop)"
# Target from stdin.
export STUB_SHA=$OK_SHA
check 2 $O Bash 'echo 99 | xargs gh pr merge --squash'
# MCP: short names blocked, PR review allowed.
check 2 $N mcp__x__create_pr ''
check 2 $N mcp__x__merge_pr ''
check 2 $N mcp__x__mark_pr_ready_for_review ''
check 0 $N mcp__github__create_pull_request_review ''
check 0 $N mcp__github__create_pr_comment ''
# A record without the stamp from stamp.sh does not count.
printf '# x\nVERDICT: APPROVED\n' >"$T/ok/.git/objection/$OK_SHA.md"
check 2 $O Bash 'gh pr create --fill --base develop'
printf '<!-- objection: sha=%s base=origin/develop -->\n# x\nVERDICT: APPROVED\n' "$(printf 'a%.0s' $(seq 40))" >"$T/ok/.git/objection/$OK_SHA.md"
check 2 $O Bash 'gh pr create --fill --base develop'
printf '%s\n# x\nVERDICT: APPROVED\n' "$stamp" >"$T/ok/.git/objection/$OK_SHA.md"
# Help and disabling auto-merge touch no PR.
export STUB_SHA=deadbeef
check 0 $N Bash 'gh pr create --help'
check 0 $N Bash 'gh pr merge --help'
check 0 $N Bash 'gh pr merge --disable-auto 5'

# --- stamp.sh ------------------------------------------------------------
R="$T/stamp"
git init -q "$R" && optin "$R" && gitc -C "$R" add . && gitc -C "$R" commit -q -m base
git -C "$R" update-ref refs/remotes/origin/develop HEAD
printf 'x\n' >"$R/a.ts" && git -C "$R" add a.ts && gitc -C "$R" commit -q -m code
printf '# doc\n' >"$R/b.md" && git -C "$R" add b.md && gitc -C "$R" commit -q -m doc
printf 'VERDICT: APPROVED\n' >"$T/min.md"
full() { printf '# D\n\n## Accusation\nx\n\n## Defense\nx\n\n## Judge\nx\n\n## Open\n%s\n\nVERDICT: APPROVED\n' "$1" >"$T/rec.md"; }
stampcheck() { # expected base record
  (cd "$R" && bash "$STAMP" "$3" "$2" >/dev/null 2>&1); local rc=$?
  if { [ "$1" = 0 ] && [ $rc != 0 ]; } || { [ "$1" != 0 ] && [ $rc = 0 ]; }; then
    echo "FAIL stamp (expected $1, got $rc): base=$2 record=$3"; failures=$((failures + 1))
  fi
}
# Arbitrary base (HEAD~1) would fall into the docs exemption.
stampcheck 1 HEAD~1 "$T/min.md"
stampcheck 1 origin/develop "$T/min.md"
full '- MEDIUM: no test for case X yet'
stampcheck 0 origin/develop "$T/rec.md"
head -1 "$R/.git/objection/$(git -C "$R" rev-parse HEAD).md" | grep -q "^<!-- objection: sha=$(git -C "$R" rev-parse HEAD) base=origin/develop -->$" \
  || { echo "FAIL: stamp.sh did not write the stamp"; failures=$((failures + 1)); }
full 'HIGH: no list marker'
stampcheck 1 origin/develop "$T/rec.md"
full '1. **High** bold severity'
stampcheck 1 origin/develop "$T/rec.md"
full 'no HIGH finding is left'
stampcheck 0 origin/develop "$T/rec.md"
# The debate's own prompts (.claude/*.md) are not "documentation only".
mkdir -p "$R/.claude/agents" && printf 'x\n' >"$R/.claude/agents/c.md"
git -C "$R" add .claude && gitc -C "$R" commit -q -m prompt
git -C "$R" update-ref refs/remotes/origin/develop HEAD~1
stampcheck 1 origin/develop "$T/min.md"
# Repository not opted in: stamp.sh refuses.
(cd "$F" && bash "$STAMP" "$T/rec.md" origin/main >/dev/null 2>&1) && { echo "FAIL: stamp.sh ran without objection.json"; failures=$((failures + 1)); }

# A record quoting APPROVED but ending REJECTED: blocked.
printf '%s\n# x\nexample: VERDICT: APPROVED\nVERDICT: APPROVED\nVERDICT: REJECTED\n' "$stamp" >"$T/ok/.git/objection/$OK_SHA.md"
check 2 $O Bash 'gh pr create --fill --base develop'

if [ "$failures" = 0 ]; then echo "require-objection: all cases passed"; else echo "require-objection: $failures failure(s)"; exit 1; fi
