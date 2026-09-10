---
name: make-agent
description: Creates new repo-native agent profiles from plan to scaffolded `agents/<name>.md` and catalog alignment. Use when adding an agent profile to this repository.
user-invocable: true
disable-model-invocation: true
---

# Make Agent

## Core Contract

Create one new agent profile in this repository as a single markdown file under `agents/`.
Start with a brief plan and explicit assumptions.
Follow `CLAUDE.md` / `AGENTS.md` on conflict.

## Agent Profile Contract

An agent profile is one `.md` file whose body is the subagent system prompt.

Location contract:

- Preferred path: `agents/<name>.md`.
- Optional grouping directories are cosmetic (`agents/<group>/<name>.md`).
- Frontmatter `name:` is the identity and must stay repo-unique.

Required frontmatter:

```yaml
name: agent-name
description: Third-person summary ending with "Delegate when ..."
model: openai-codex/gpt-5.6-luna
tools: read, grep, glob, find, ls, bash, edit, write, intercom
thinking: medium
```

- `name`: required; lowercase-hyphenated; repo-unique; should match filename.
- `description`: required; third person; ends with `Delegate when ...`.
- `model`: required; `provider/model` selector. Prefer `openai-codex/*`, which
  bills against the ChatGPT subscription, over metered `anthropic/*`.
- `tools`: required; least-privilege.
- `thinking`: `low` for recon, `medium` for normal work, `high` for adjudication.

### Dual-harness frontmatter

One profile is installed to both pi and OMP, which read different keys. Under pi
the reader is the `pi-interactive-subagents` extension
(`pi-extension/subagents/index.ts`); under OMP it is `parseAgentFields()`. Both
ignore keys and tool names they do not recognise, so a union works — but a
misspelled key is silently dead rather than rejected.

| Key | pi | OMP | Rule |
| --- | --- | --- | --- |
| `model` | single selector | CSV priority list | Keep a single selector. |
| `tools` | pi vocabulary | OMP vocabulary | Union both; each side drops what it does not know. |
| `thinking` | honoured | honoured | Safe. |
| `system-prompt` | `replace` \| `append` | ignored | pi's real key. **Not** `systemPromptMode`. |
| `session-mode` | `fork` \| `lineage-only` \| `standalone` | ignored | pi's real key. **Not** `defaultContext`. |
| `skills`, `deny-tools`, `spawning`, `auto-exit`, `interactive`, `cwd`, `cli`, `disable-model-invocation` | honoured | ignored | pi-only, correctly spelled. |
| `read-summarize` | ignored | verbatim reads when `false` | Set `false` for recon agents. |
| `spawns`, `blocking`, `autoloadSkills`, `prewalk`, `advisor` | ignored | honoured | OMP-only. |
| `output` | ignored | **structured-output schema** | Never use. See below. |
| `fallbackModels`, `inheritProjectContext`, `inheritSkills`, `defaultReads`, `defaultContext`, `defaultProgress`, `systemPromptMode` | **dead** | **dead** | Invented keys with no consumer in either harness. Never add. |

That last row is not hypothetical: every one of those keys shipped in this
repo's profiles and none was ever read. Grep the harness that will consume a key
before adding it.

Tool-name vocabulary: `read`, `grep`, `bash`, `edit`, `write`, `web_search` exist
in both. `find` and `ls` are pi-only. `glob`, `lsp`, `ast_grep`, `yield`, and `hub`
are OMP-only. `intercom`, `contact_supervisor`, `fetch_content`, and
`get_search_content` come from pi extensions. List every name the agent needs on
either harness in one CSV.

Two caveats confirmed by probing a live subagent: `ast_grep` stays unavailable
until `astGrep.enabled` is set (default `false`), and OMP grants `yield`, `hub`,
and `write` whether or not they are listed. A read-only agent therefore needs the
restriction stated in its body, not just withheld from `tools`.

**Never set `output:` to a filename.** OMP reads it as a structured-output
schema, and a bare string is not one. The agent
then fails its dispatch with `Subagent called yield with null data` whenever it
returns prose. Instead, name the artifact in the body: write to the path when the
dispatcher supplies one, otherwise return the report inline.

Body contract:

- Imperative, single-role, and self-contained instructions.
- Include stop-and-ask guidance when ambiguity affects behavior or safety.
- Include the override rule: target repo `CLAUDE.md`/`AGENTS.md` wins on conflict.
- Do not claim a specific harness ("running inside pi"); the profile runs on both.

### Name collisions with OMP bundled agents

OMP ships bundled agents named `scout`, `reviewer`, `designer`, `security-reviewer`,
`librarian`, `task`, and `sonic`. Discovery is first-wins by name, and user agents
outrank bundled ones, so a profile using one of those names **replaces** the
bundled agent under OMP. Taking a bundled name is a deliberate act: match or beat
what it provided (read-only tool set, `read-summarize: false`, role-aliased model)
rather than silently regressing it.

## Required Inputs

1. Agent purpose and boundaries.
2. Proposed name (if any).
3. Tooling constraints / least-privilege requirements.
4. Model preference (if any).
5. Expected outputs or reporting style.

## Workflow

1. Restate request and produce a compact creation plan.
2. List assumptions (`safe default` vs `needs confirmation`).
3. Ask only high-impact clarifying questions.
4. Normalize/derive agent name and validate repo uniqueness.
5. Create `agents/<name>.md` with compliant frontmatter and prompt body.
6. Ensure prompt includes stop-and-ask gates and override rule.
7. Add a concise `README.md` catalog entry under the Agents section.
8. Verify naming alignment (`name`, filename, and references) and catalog sync.

Stop and ask if request spans multiple agents, name conflicts with existing tools/agents, or ambiguity changes behavior/safety.

## Safety Rules

- Never scaffold an agent before name uniqueness is confirmed in this repo.
- Never grant more tools than required for the agent's role.
- Never hide assumptions; label and confirm high-impact ones.
- Never skip clarifications when ambiguity affects behavior, safety, or permissions.
- Never silently broaden scope beyond one requested agent without user approval.
- Never leave `README.md` out of sync after adding, renaming, or removing an agent.

## Output Style

Report final agent name/path, assumptions confirmed, defaults applied, and any optional follow-up improvements.
