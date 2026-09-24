# claude-debate

**Adversarial review for Claude Code. Every PR is debated before it exists.**

When you ask an AI to build something, it plans, writes, checks, and
approves its own work. It is the same mind grading its own exam. This
plugin splits that into roles that argue:

```
                 ┌──────────────┐
  your diff ───▶ │  ACCUSATION  │  accuser + your specialist reviewers, in parallel
                 └──────┬───────┘  every finding needs file:line and a proof path
                        ▼
                 ┌──────────────┐
                 │   DEFENSE    │  defender tries to REFUTE each finding with code;
                 └──────┬───────┘  when in doubt, the finding stands
                        ▼
                 ┌──────────────┐
                 │    JUDGE     │  the main session: checks every refutation,
                 └──────┬───────┘  cannot dismiss anything alone, ties go to a test
                        ▼
                 ┌──────────────┐
                 │    RECORD    │  stamped to the exact commit SHA and base
                 └──────┬───────┘
                        ▼
  gh pr create / ready / merge  ── blocked by a hook until the record says APPROVED
```

Only what survives the defense becomes a fix. The record goes into the PR
body, so reviewers see what was rejected and what was fixed because of it.

## Why

It came from two real projects where, over the last 300 commits, `fix:`
commits outnumbered `feat:` commits almost two to one. The defect shipped
and came back as a fix. Review existed as a rule written in `CLAUDE.md`,
and a written rule stops nothing.

Two design decisions carry most of the value:

- **A defender, not just more reviewers.** Reviewers are rewarded for
  finding things, so they also find things that are not there, and a false
  finding sends someone to "fix" correct code. The defender refutes with
  `file:line` or not at all. The burden of proof is on the defense.
- **A gate, not a suggestion.** The hook makes the debate the condition
  for the PR to exist. A new commit after the debate invalidates the
  record.

**No finding quotas.** Prompts like "find at least three problems" make
the model invent the third one. The accusers are asked what they could
*not* evaluate instead.

## Install

In Claude Code:

```
/plugin marketplace add victorserpa/claude-debate
/plugin install debate@claude-debate
```

Then, in each repository you want to protect:

```
/debate init
```

This creates `.claude/debate.json`. **Nothing is enforced in a repository
without that file**, so installing the plugin never blocks work in
repositories you did not opt in.

```json
{
  "bases": ["develop", "main"],
  "defaultBase": "develop",
  "verify": ["pnpm typecheck", "pnpm test"],
  "reviewers": [
    { "paths": "^apps/api/src/(auth|billing)/", "agent": "security-reviewer", "focus": "the project's security checklist" },
    { "paths": "^packages/db/migrations/", "agent": "accuser", "focus": "destructive SQL and deploy order" }
  ]
}
```

| key | meaning |
|---|---|
| `bases` | every branch a PR may target; a record is only valid against the base it was debated on |
| `defaultBase` | what `gh pr create` targets without `--base` |
| `verify` | cheap proof (types, tests) that must pass before any agent runs |
| `reviewers` | your own agents from `.claude/agents/`, added as accusers when the diff touches `paths` |

Requirements: `node`, `git`, and the `gh` CLI.

## Use

When a branch is ready: `/debate`. When Claude tries to open a PR without
one, the hook blocks it and tells it to run `/debate`.

A human can always bypass the gate by running `gh` in their own terminal.
The hook binds the agent, not you.

## What the hook blocks

Without an APPROVED, stamped record for the exact SHA and base:

- `gh pr create` / `new` / `ready` / `merge`, however they are invoked:
  `gh -R x pr …`, `$(…)`, `bash -c`, `xargs`, piped into a shell,
  `\gh`, absolute paths
- `gh pr merge --auto` (it would let in commits pushed after the debate)
- `gh api` writes to `/pulls` or `/pulls/<n>/merge`, and GraphQL PR
  mutations (including multi-line queries and queries read from a file)
- MCP tools that create, update, mark ready, or merge a PR

It does not block reading PRs, commenting, reviewing, or any command that
merely *mentions* those commands (commit messages, `grep`, `echo`,
heredoc bodies).

**The hook went through its own debate before release.** Round one found
12 ways around the first (bash) version, including a record ending in
`REJECTED` that quoted `APPROVED` and still passed. Round two, with the
defender, found 10 more. Every one is a regression case in
[`test/require-debate.test.sh`](test/require-debate.test.sh).

## Honest limits

- It is a **process guard, not a security boundary.** An agent determined
  to cheat could write a fake record and stamp it. The skill forbids it in
  writing, and the record is public in the PR body.
- `curl` against the GitHub API with a token from `gh auth token` is not
  blocked.
- It costs two to five Opus agents per round, once per PR. A small PR
  makes a short debate.

## How it compares to Ruflo

[Ruflo](https://github.com/ruvnet/ruflo) (formerly claude-flow) is a large
multi-agent orchestration platform. If you want swarms, vector memory, and
100+ agents, look there. This plugin does one thing: make sure no PR
ships unless someone other than its author tried to break it.

| | claude-debate | Ruflo (`ruflo-core` plugin, checked 2026-09-23) |
|---|---|---|
| Focus | a debate record per commit before any PR | multi-agent orchestration platform |
| MCP server | none | registers one with 300+ tools |
| Runtime downloads | none; ~500 lines of Node and bash | hooks and MCP fall back to `npx …@latest` |
| Hooks | one `PreToolUse`, inert without `.claude/debate.json` | on every Bash, Edit, compaction and stop |
| Agents | 2 (accuser, defender) + yours | 100+ |

## Layout

```
.claude-plugin/marketplace.json
plugins/debate/
  .claude-plugin/plugin.json
  agents/accuser.md          prosecution
  agents/defender.md         defense
  hooks/hooks.json
  hooks/require-debate.mjs   the gate
  skills/debate/SKILL.md     the procedure
  skills/debate/stamp.sh     validates and stores the record
test/require-debate.test.sh
```

Run the tests with `bash test/require-debate.test.sh`.

## License

MIT
