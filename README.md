# Agentic tools

Reusable tools for real engineering work across machines and projects.

| Tool Type | Description |
| --- | --- |
| **Skills** | Portable `SKILL.md` workflows for reliable end-to-end tasks. |
| **Agent profiles** | Claude Code subagents I can delegate focused work to. |

## Quick Start

Clone the repo:
```sh
git clone git@github.com:nanstey/agentic-tools.git
```

Install or update the tools:
```sh
bash install.sh
```

## Harnesses

`harness/` stores portable, non-secret configuration for supported agent
harnesses. Expand a harness below for its managed files, install destinations,
and runtime behavior.

<details>
<summary><code>harness/pi/</code> (Pi)</summary>

`install.sh` copies the Pi configuration into `$PI_AGENT_DIR`, which defaults to
`~/.pi/agent` and follows `PI_CODING_AGENT_DIR` when set. These files are copied
rather than symlinked because Pi may rewrite them locally.

| Repository path | Install destination | Purpose |
| --- | --- | --- |
| `harness/pi/settings.json` | `$PI_AGENT_DIR/settings.json` | Defaults and Pi's extension package list, including `npm:pi-intercom@0.12.0`. |
| `harness/pi/extensions/*.json` | `$PI_AGENT_DIR/extensions/` | Per-extension config. |
| `harness/pi/extensions/pi-interactive-subagents/config.json` | `$PI_AGENT_DIR/extensions/pi-interactive-subagents/config.json` | Interactive-subagents config. |
| `harness/pi/extensions/pi-intercom/config.json` | `$PI_AGENT_DIR/intercom/config.json` | Shared pi-intercom config: enabled inbound replies, no send confirmation, and reply hints. |
| `harness/pi/command-shortcuts.json` | `$PI_AGENT_DIR/command-shortcuts.json` | Command shortcut bindings. |
| `harness/pi/keybindings.json` | `$PI_AGENT_DIR/keybindings.json` | Custom keybindings. |

When either Pi or OMP is installed, `install.sh` copies the same
`harness/pi/extensions/pi-intercom/config.json` source to
`$PI_AGENT_DIR/intercom/config.json`. pi-intercom also stores its runtime state
under `$PI_AGENT_DIR/intercom`.

Secrets and machine-local state (`auth.json`, `auth-profiles/`, `web-search.json`,
`trust.json`, sessions, run history) are git-ignored and never travel — re-auth
per machine with `/login`.

To pull live config changes back into the repo, use the [`pi-sync`](.agents/skills/pi-sync/SKILL.md)
skill (allowlist-based; it never reads or copies secrets).

### New machine bootstrap
```sh
git clone git@github.com:nanstey/agentic-tools.git ~/Code/skills
cd ~/Code/skills && bash install.sh   # links tools, copies harness config
pi                                     # installs packages from settings.json
/login anthropic                       # re-auth (secrets are never synced)
```

</details>

<details>
<summary><code>harness/omp/</code> (OMP)</summary>

`install.sh` links shared skills and agents into `~/.omp/agent` and every
existing `~/.omp/profiles/*/agent`, copies portable OMP config to each, applies
the versioned status-line and model-role settings, and installs the packages
below with OMP's native `omp install` command:

| Repository path | Install destination | Purpose |
| --- | --- | --- |
| [`harness/omp/APPEND_SYSTEM.md`](harness/omp/APPEND_SYSTEM.md) | `~/.omp/agent/APPEND_SYSTEM.md` | Adds bounded delegation and collision-safe temporary-file guidance. |
| [`harness/omp/plugins/pi-intercom.txt`](harness/omp/plugins/pi-intercom.txt) | Not copied; passed to `omp install` | Installs `npm:pi-intercom@0.12.0`. Blank and comment lines are ignored. |
| [`harness/omp/status-line/apply.sh`](harness/omp/status-line/apply.sh) | Default and existing profile `config.yml` files (via `omp config`) | Selectively merges the versioned Nerd Font status-line schema. |
| [`harness/omp/model-roles/apply.sh`](harness/omp/model-roles/apply.sh) | Default and existing profile `config.yml` files (via `omp config`) | Merges the versioned `modelRoles` tiers (`smol`, `task`, `slow`, `designer`) that bundled agents select through `@role` aliases, plus the `task.agentModelOverrides` pins. Leaves `modelRoles.default` alone. |

The installer copies each top-level, non-dot file under `harness/omp/` as a whole
file into every OMP agent dir. Nested files such as the plugin manifest and the
applicator scripts are not
copied. A differing destination file is replaced, so local edits to a managed
file such as `APPEND_SYSTEM.md` are clobbered the next time `install.sh` runs.
Native OMP package installation failure exits the installer with an error.

After copying OMP artifacts for a detected OMP harness, `install.sh` runs each
applicator against `~/.omp/agent/config.yml` and each existing
`~/.omp/profiles/*/agent/config.yml`. Every applicator owns an explicit key list,
compares each managed value with `omp config get`, and calls `omp config set`
only for differences. Unrelated and profile-local settings—including
`composer.shape`, `modelRoles.default`, `webSearchOrder`, and `setupVersion`—remain
untouched; reruns are idempotent. There is no copied `harness/omp/config.yml`.

Bundled OMP agents (`scout`, `librarian`, `sonic`, `reviewer`, `task`,
`designer`) pick their model through `@smol`, `@slow`, `@task`, and `@designer`
aliases. An unmapped alias silently falls back to the parent session's active
model, which runs cheap recon agents on an expensive session model, so the
model-roles applicator keeps those four tiers mapped and pins `sonic`, the
strictly mechanical agent, to the cheapest tier at low effort.

Tier selection follows billing, not list price: `openai-codex` is authenticated
by OAuth against a ChatGPT plan, so its models bill against that subscription,
while `anthropic` runs on a metered API key. The light, high-volume tiers
(`smol`, `task`, `slow`) therefore stay on codex models, and `designer` uses
Sonnet rather than Fable ($2/$10 per Mtok instead of $10/$50).

The custom Nerd Font line uses each profile's chosen composer. It groups model,
compact context usage such as `39.0%/272K`, Git state, and session name on the
left, with elapsed time right-aligned. OMP keeps the status on one adaptive row
and drops trailing segments as width narrows.

To cap subagents at one delegation level, create or edit the machine-local file:

```yaml
task:
  maxRecursionDepth: 1
```

</details>

## Skills

### Dev

| Skill | Description |
| --- | --- |
| [`changes`](skills/dev/changes/SKILL.md) | Summarize staged/unstaged changes into logical groups and flag unrelated edits. Read-only. |
| [`build`](skills/dev/build/SKILL.md) | Implements scoped changes from context, plans, or speclists through verifiable phases with up-front success criteria and per-phase validation. |
| [`commit`](skills/dev/commit/SKILL.md) | Group current changes into clean commit(s), run hooks, and push to `origin` by default. |
| [`rebase`](skills/dev/rebase/SKILL.md) | Rebase onto latest `main`/`develop`; hand conflicts to `conflicts`; force-push with lease. |
| [`conflicts`](skills/dev/conflicts/SKILL.md) | Resolve merge/rebase/cherry-pick/revert conflicts and continue the stopped operation. |
| [`branch`](skills/dev/branch/SKILL.md) | Create a new branch for current/proposed changes, deriving a conventional `<type>/<slug>` name when none is given. |
| [`worktree`](skills/dev/worktree/SKILL.md) | Create or reuse a git worktree for a branch — Orca-managed when the Orca IDE runs the repo, plain git otherwise — and report its path. Triggered before starting any new unit of work. |
| [`prototype`](skills/dev/prototype/SKILL.md) | Build a throwaway prototype (interactive logic TUI or switchable UI variants) to answer a design question, then capture the answer and delete it. |

### Env

| Skill | Description |
| --- | --- |
| [`worktree-env`](skills/env/worktree-env/SKILL.md) | Builds a project-specific, idempotent worktree bootstrap that copies approved local configuration, installs dependencies, and allocates collision-free service ports. Use when a repository needs repeatable isolated development environments for Git or Orca worktrees. |
| [`new-app`](skills/env/new-app/SKILL.md) | Scaffolds a new local software project from scratch — folder structure, git, README, LICENSE, .gitignore, optional CI, and a first commit — delegating language-specific init to the ecosystem's own tool. Use when starting a brand-new local application. |
| [`new-repo`](skills/env/new-repo/SKILL.md) | Creates and configures a private GitHub repository for an existing local git project, including protected-main and squash-only policy. Use when a local repository needs a GitHub remote. |
| [`orca-repo`](skills/env/orca-repo/SKILL.md) | Registers an existing local git repository with the Orca IDE and verifies it is tracked, optionally setting its base ref. Use when a local repository should appear in Orca. |

### Planning

Focused planning skills below are optional and independently selectable; `proposal` and `speclist` remain separate planning paths. `plan-init` groups a change's artifacts into one plan folder with a README index that later skills and `build` share.

| Skill | Description |
| --- | --- |
| [`plan-init`](skills/planning/plan-init/SKILL.md) | Creates a plan folder with a README index so a change's planning artifacts and per-slice specs live together and stay linked. Use when starting planning that will produce multiple related documents or feed a build. |
| [`proposal`](skills/planning/proposal/SKILL.md) | Runs discovery and uncertainty resolution for a change, then writes one self-contained plan document covering purpose, behaviour, validation, architecture, and phased vertical slices. Use for a small or trivial change simple enough to plan in a single document rather than decomposed focused artifacts. |
| [`speclist`](skills/planning/speclist/SKILL.md) | Convert reports into ordered implementation checklists with blockers and validation steps. |
| [`product-review`](skills/planning/product-review/SKILL.md) | Turns a product request into a concise user-centred review with outcomes, success signals, and scope. Use when an agent misunderstanding the product intent would be expensive. |
| [`system-architecture`](skills/planning/system-architecture/SKILL.md) | Produces a bounded system architecture artifact covering boundaries, contracts, and data flow. Use when a change crosses components or carries consequential technical design choices. |
| [`program-design`](skills/planning/program-design/SKILL.md) | Produces a concise code-shape design with call paths, file placement, and key interfaces. Use when an implementation could go wrong despite a settled architecture or local requirement. |
| [`vertical-slices`](skills/planning/vertical-slices/SKILL.md) | Breaks a change into small observable implementation increments with verification checkpoints. Use when a plan risks becoming a large horizontal batch of layer-by-layer work. |

### Workflow

| Skill | Description |
| --- | --- |
| [`idea-to-pr`](skills/workflow/idea-to-pr/SKILL.md) | Takes an idea from evidence-backed discovery through built, tested, and validated pull requests. Use when a feature idea or change request should be driven end-to-end to review-ready PRs. |
| [`flow-design`](skills/workflow/flow-design/SKILL.md) | Designs a platform-neutral delegation plan with roles, gates, and return contracts. Use when a task needs coordinated execution designed before work begins. |

### Agent

| Skill | Description |
| --- | --- |
| [`context-engineering`](skills/agent/context-engineering/SKILL.md) | Audit a scope (skill, system prompt, tool set, CLAUDE.md, project) against context engineering best practices and apply improvements. |
| [`scope`](skills/agent/scope/SKILL.md) | Confirm and normalize analysis scope, then return clear scope assumptions before scanning files. |
| [`reflect`](skills/agent/reflect/SKILL.md) | Review the current session for problems and their fixes, then propose durable improvements to repo skills, scripts, or docs that prevent recurrence. |

### Writing

| Skill | Description |
| --- | --- |
| [`terse`](skills/writing/terse/SKILL.md) | Keep responses concise, outcome-first, and high signal. |
| [`write-docs`](skills/writing/write-docs/SKILL.md) | Write clear, precise project documentation that describes behaviour and relationships in plain language. |
| [`deslop`](skills/writing/deslop/SKILL.md) | Remove AI writing patterns, tells, and formulaic slop from prose. |
| [`bluf`](skills/writing/bluf/SKILL.md) | Structure a message bottom-line-first, stating the main point or request before its supporting context. |
| [`prep`](skills/writing/prep/SKILL.md) | Structure a persuasive case as Point, Reason, Example, Point so a recommendation lands with evidence. |
| [`grow`](skills/writing/grow/SKILL.md) | Structure current-to-future planning as Goal, Reality, Options, Will to bridge a current state to a target. |
| [`observation-impact-question`](skills/writing/observation-impact-question/SKILL.md) | Structure lightweight feedback as Observation, Impact, Question to stay specific and non-accusatory. |
| [`before-after-bridge`](skills/writing/before-after-bridge/SKILL.md) | Structure a results story as Before, After, Bridge so a demo or outcome leads with impact. |

### Visual

| Skill | Description |
| --- | --- |
| [`visual-capture`](skills/visual/visual-capture/SKILL.md) | Capture screenshots and videos of a running site (before/after PR evidence, component crops, multi-page or scroll tours) by driving the `playwright-cli` tool. |

### Tools

| Skill | Description |
| --- | --- |
| [`playwright-cli`](skills/tools/playwright-cli/SKILL.md) | Drive a browser from the CLI — navigate, interact, snapshot, screenshot, record video, mock network, and run/generate Playwright tests. Vendored from `microsoft/playwright-cli` (Apache-2.0). |
| [`chrome-devtools-cli`](skills/tools/chrome-devtools-cli/SKILL.md) | Automate browser tasks and use Chrome DevTools from the CLI. Vendored from `ChromeDevTools/chrome-devtools-mcp` (Apache-2.0). |

### Pull Requests

| Skill | Description |
| --- | --- |
| [`pr`](skills/pull-requests/pr/SKILL.md) | Prepares a branch and invokes `pr-monitor` once for PR reconciliation. |
| [`pr-info`](skills/pull-requests/pr-info/SKILL.md) | Find and verify the branch PR (or a URL) and load its metadata. Read-only. |
| [`pr-monitor`](skills/pull-requests/pr-monitor/SKILL.md) | Reconciles one verified open PR to a stable review-ready state. |
| [`pr-ci`](skills/pull-requests/pr-ci/SKILL.md) | Diagnose failed PR CI jobs, fix root causes, validate, commit, and push. |
| [`pr-create`](skills/pull-requests/pr-create/SKILL.md) | Create a draft PR for the current branch when none exists. |
| [`pr-comments`](skills/pull-requests/pr-comments/SKILL.md) | Triage unresolved review threads, apply fixes, validate, commit, push, and resolve/reply. |
| [`pr-description`](skills/pull-requests/pr-description/SKILL.md) | Sync the PR title and description to current branch changes and maintain checklist accuracy. |
| [`pr-screenshots`](skills/pull-requests/pr-screenshots/SKILL.md) | Keep a PR's screenshots and UI clips in sync with the current UI implementation, capturing or refreshing them (as PR attachments, never committed) when the branch changes UI. |
| [`pr-rebase`](skills/pull-requests/pr-rebase/SKILL.md) | Rebase onto latest `origin/develop`, resolve conflicts, and force-push with lease. |
| [`pr-restack`](skills/pull-requests/pr-restack/SKILL.md) | Rebase dependent PR stacks and repoint downstream branches to correct bases. |
| [`pr-split`](skills/pull-requests/pr-split/SKILL.md) | Split a large branch/PR into smaller reviewable units, proposing parallel PRs or a stacked series. |
| [`gh-stack`](skills/pull-requests/gh-stack/SKILL.md) | Create and manage GitHub native stacked-PR stacks via the gh-stack CLI or Stacks REST API, with fallback when the feature is unavailable. |

### Issues

| Skill | Description |
| --- | --- |
| [`issue-create`](skills/issues/issue-create/SKILL.md) | Create a GitHub issue from context and optional metadata. |

### Code quality

| Skill | Description |
| --- | --- |
| [`deep-review`](skills/code-quality/deep-review/SKILL.md) | Strict maintainability review focused on abstractions, oversized files, and condition sprawl. |
| [`dry`](skills/code-quality/dry/SKILL.md) | Read-only DRY review that ranks duplication and proposes concrete consolidations. |
| [`srp`](skills/code-quality/srp/SKILL.md) | Evaluate Single Responsibility Principle violations and recommend cohesive boundaries. |
| [`extract`](skills/code-quality/extract/SKILL.md) | Identify extraction opportunities from DRY/SRP findings and propose reusable boundaries. |
| [`principles`](skills/code-quality/principles/SKILL.md) | Apply core design principles through a concise implementation/review checklist. |
| [`sniff`](skills/code-quality/sniff/SKILL.md) | Run smell analysis and map findings to standard smells and refactor options. |
| [`fresh-air`](skills/code-quality/fresh-air/SKILL.md) | Recommend best-fit refactoring techniques for smell findings with confidence. |
| [`refactor`](skills/code-quality/refactor/SKILL.md) | Orchestrate smell validation, technique selection, and final implementation planning. |
| [`scrutiny`](skills/code-quality/scrutiny/SKILL.md) | Silently interrogates a build/design across the relevant engineering domains, self-answering what the codebase and defaults allow and escalating only authority decisions, then builds and verifies. Vendored and adapted from [m4vic/socratic](https://github.com/m4vic/socratic) (MIT). |

### Authoring (project skills)

| Skill | Description |
| --- | --- |
| [`check-skill-name`](.agents/skills/check-skill-name/SKILL.md) | Check skill names for collisions and return CLEAR/CONFLICT/RISKY plus safe alternatives. |
| [`pi-sync`](.agents/skills/pi-sync/SKILL.md) | Capture portable, non-secret pi config from a live `~/.pi/agent` into `harness/pi/` and commit it, without touching secrets. |
| [`make-skill`](.agents/skills/make-skill/SKILL.md) | Plan and scaffold a convention-compliant repo skill, including name validation. |
| [`make-agent`](.agents/skills/make-agent/SKILL.md) | Plan and scaffold a convention-compliant repo agent profile and align the catalog. |

## Agents

Claude Code subagents for focused delegated work.

| Agent | Description |
| --- | --- |
| [`worker`](agents/worker.md) | Implementation agent for normal tasks and approved oracle handoffs. Single writer thread; escalates unapproved decisions via `contact_supervisor`. |
| [`scout`](agents/scout.md) | Fast codebase recon that returns compressed context for handoff. Writes `context.md`. |
| [`researcher`](agents/researcher.md) | Autonomous web researcher — searches, evaluates, and synthesizes a focused research brief into `research.md`. |
| [`planner`](agents/planner.md) | Creates concrete implementation plans from context and requirements. Read-only; writes `plan.md`. |
| [`reviewer`](agents/reviewer.md) | Versatile review specialist for code diffs, plans, proposed solutions, codebase health, and PR/issue validation. |
| [`context-builder`](agents/context-builder.md) | Analyzes requirements and codebase; generates `context.md` and `meta-prompt.md` for planning and subagent handoffs. |
| [`oracle`](agents/oracle.md) | High-context decision-consistency oracle that protects inherited state and prevents drift. Read-only. |
| [`delegate`](agents/delegate.md) | Lightweight, low-cost generic subagent with no default reads. General-purpose delegated execution. |
