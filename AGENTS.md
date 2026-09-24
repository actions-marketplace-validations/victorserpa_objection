# Working on objection

Instructions for any AI agent (and human) changing this repository.

## Commits: mandatory

- **Conventional Commits, in English**: `type(scope)!: description`, with
  `feat`, `fix`, `docs`, `refactor`, `test`, `ci`, `chore`, `perf`,
  `build`, `style` or `revert`. Subject in plain English, no accents.
- **Never add a `Co-Authored-By` trailer**, for any tool or person.
- Enforced locally by `.githooks/commit-msg` (run
  `git config core.hooksPath .githooks` once per clone) and in CI for
  every commit of a PR, both through `scripts/check-commit-msg.sh`.

## Layout

| path | what |
|---|---|
| `skills/objection/` | the skill, self-contained: `SKILL.md`, `roles/`, `stamp.sh`, `gate/`, `templates/` |
| `skills/objection/gate/core.mjs` | the gate logic, tool-neutral |
| `skills/objection/gate/hook.mjs` | pre-tool hook adapter (Claude Code, Codex, Gemini CLI, Cursor) |
| `skills/objection/gate/check-pr.mjs` | the GitHub check (`action.yml`) |
| `agents/` | Claude Code subagents; body must equal `skills/objection/roles/` |
| `.claude-plugin/`, `hooks/hooks.json` | Claude Code plugin and marketplace |
| `test/` | regression cases |

## Before committing

```bash
bash test/gate.test.sh
bash test/check-pr.test.sh
bash test/roles-in-sync.test.sh
claude plugin validate .
```

- Every bypass of the gate that gets found becomes a case in
  `test/gate.test.sh` before the fix.
- Changing a role? Change `skills/objection/roles/<role>.md` and the body
  of `agents/<role>.md` together.
- Host formats (hook input and output for Codex, Gemini CLI, Cursor,
  Copilot) come from the hosts' official docs. Do not describe a format
  in code or README that was not checked against them; say "unverified"
  instead.
- Do not make claims about other projects (Ruflo, etc.) that were not
  checked against their source.
