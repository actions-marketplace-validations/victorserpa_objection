---
name: debate
description: Adversarial review before opening or merging a PR. Accusers review the diff, a defender tries to refute each finding with evidence from the code, and the main session judges and stores a record for the exact commit. In repositories with .claude/debate.json, the require-debate hook blocks gh pr create, ready and merge without an APPROVED record. Use when a branch is ready for a PR, when the hook blocks, or with "init" to opt a repository in.
---

# /debate

Whoever wrote the code does not approve the code. The debate puts
different agents in opposite roles: the accusation looks for defects,
the defense tries to refute each accusation with evidence, and the judge
decides. Only what survives the defense becomes a fix.

**Every PR, whatever its size.** Do not route around the hook (`gh api`,
a GitHub MCP tool, `curl` with a token, asking the human to run it for
you without saying the debate did not run). If it blocked, run the
debate.

## init: opting a repository in

If `.claude/debate.json` does not exist and the user asked for `init`
(or the debate is being run for the first time), create it. Ask the user
only what you cannot read from the repository:

```json
{
  "bases": ["main"],
  "defaultBase": "main",
  "verify": ["npm run typecheck", "npm test"],
  "reviewers": [
    { "paths": "^src/(auth|billing)/", "agent": "security-reviewer", "focus": "the project's security checklist" },
    { "paths": "^migrations/", "agent": "accuser", "focus": "destructive SQL, lock time, order against deploy" }
  ]
}
```

- `bases`: every branch a PR may target (e.g. `["develop", "main"]`).
- `defaultBase`: what `gh pr create` uses without `--base`.
- `verify`: the cheap proof that runs before any agent (step 0).
- `reviewers`: extra accusers by path regex. `agent` is any agent the
  project has (`.claude/agents/`) or this plugin's `accuser`; `focus` goes
  into its prompt. The plugin `accuser` always runs on code, so this list
  can start empty.

Commit the file. From then on the hook enforces the debate in this
repository.

## 0. Before the debate: the cheap proof

A debate is argument; a test is proof. Do not spend expensive agents on
code that does not pass.

1. Everything committed. The record is for one SHA, and anything outside
   the commit was not debated.
2. Base: the branch the PR targets, from `bases`. `git fetch origin <base>`.
3. Run every command in `verify`. Red: fix it first.
4. **Diff touching only `*.md` or `docs/`** (outside `.claude/`): skip
   steps 1 to 3. The record says "documentation only", without the debate
   sections, and goes straight to the stamp.

## 1. Accusation (in parallel)

`git diff --name-only origin/<base>...HEAD` decides who accuses. Launch
them all in one message, each with its diff (`git diff
origin/<base>...HEAD -- <its files>`) and the goal of the change in one
sentence:

- this plugin's `accuser` (shown as `debate:accuser`) on the whole code
  diff, always;
- each `reviewers` entry whose `paths` matches a changed file, with its
  `focus`.

**Rules that go into every accuser's prompt:**

- Each finding has a severity (BLOCKER, HIGH, MEDIUM, LOW), `file:line`,
  and **how to prove it**: the test that would fail or the execution path
  that reaches the defect.
- **No quota.** Never ask for "at least three problems": a quota makes
  the agent invent the third, and an invented finding is rework. Ask what
  it could not evaluate.
- Style and formatting are out.

## 2. Defense

One `defender` (shown as `debate:defender`) receives **all** BLOCKER,
HIGH and MEDIUM findings, numbered, with the proof each accuser gave. LOW
goes straight to the record, without defense.

## 3. Judge: this session, never a smaller model

A wrong diagnosis returns a plausible explanation and nobody notices. So
the main session judges, with these rules, not with opinion:

| defense said | judge does |
|---|---|
| REFUTED | opens the citation and checks it covers **exactly** the accused case. It does not: UPHELD. |
| UPHELD | fixes it, or moves it to "Open" with a reason. |
| CANNOT VERIFY | BLOCKER or HIGH: treated as UPHELD. **Tie-break by test:** write the test the accuser said would fail. Fails: UPHELD. Passes: REFUTED, and the test stays in the repository. |

**The judge never refutes a finding alone.** Refuting requires the
defender's citation, checked. The judge wrote the code, and that is the
bias the debate exists to cut.

## 4. Rounds

Fixed something: commit (a `fix:` in the same branch, before the PR, is
the cheap fix) and redo steps 0 to 3 **only on the fix diff** (`git diff
<previous-round-sha>..HEAD`), with the accusers for that area. At most
three rounds; on the fourth, stop and bring what does not converge to the
human.

## 5. Record and stamp

Write the record to a scratch file, with these exact sections:

```markdown
# Debate: <branch> @ <sha7>

## Accusation
<one finding per line: #, severity, accuser, file:line, sentence>

## Defense
<#, defender verdict, evidence>

## Judge
<#, final decision, and what was fixed (commit) or why not>

## Open
<what was left out, with severity and reason; "nothing" if nothing>

VERDICT: APPROVED
```

APPROVED only with no BLOCKER or HIGH under "Open". Then run the
`stamp.sh` that sits next to this SKILL.md:

```bash
bash <this skill's directory>/stamp.sh <record.md> origin/<base>
```

It refuses a record without the sections, with a dirty tree, with a base
outside `bases`, or APPROVED with a serious finding open. It writes a
stamp with the SHA and base on the first line; the hook only accepts
stamped records and checks the base against the PR target. Once
approved, push the debated commit and **paste the record into the PR
body**: it is the log of what the reviewers rejected and what was fixed
because of it.

## Cost

Two to five Opus agents per round. Worth it per PR, not per commit. A
three-line change makes a three-line PR, and the debate comes out short
because there is little to accuse.
