#!/usr/bin/env bash
# Merge the versioned model tiers into an OMP agent dir's config.yml.
#
# Bundled OMP agents select their model through role aliases (`@smol`, `@slow`,
# `@task`, `@designer`). An alias with no `modelRoles` entry falls back to the
# parent session's active model, so an unmapped `@smol` runs `scout` on whatever
# expensive model the main session happens to use. This applicator owns those
# tier roles and leaves `modelRoles.default` — the profile-local session model —
# alone.
#
# Cost note: `openai-codex` is authenticated by OAuth against a ChatGPT plan, so
# its models bill against that subscription rather than per token. `anthropic`
# runs on a metered API key. Light, high-volume tiers therefore stay on codex
# models, and the metered provider is reserved for work that needs it.
set -euo pipefail

omp_bin="${OMP_BIN:-omp}"
agent_dir="${1:-${PI_CODING_AGENT_DIR:-$HOME/.omp/agent}}"

if ! command -v "$omp_bin" >/dev/null 2>&1; then
  echo "  [model-roles] omp unavailable, skipping"
  exit 0
fi
if ! command -v jq >/dev/null 2>&1; then
  echo "  [model-roles] jq unavailable, skipping"
  exit 0
fi

run_omp() {
  env -u OMP_PROFILE PI_CODING_AGENT_DIR="$agent_dir" "$omp_bin" "$@"
}

# Keep these lists explicit: they are the only config this applicator owns.
# `modelRoles.default` is deliberately absent — each profile picks its own
# session model.
ROLES=(
  "smol=openai-codex/gpt-5.6-luna:low"         # scout, librarian, sonic, prewalk
  "task=openai-codex/gpt-5.6-terra:medium"     # generic task agent
  "slow=openai-codex/gpt-5.6-sol:high"         # bundled reviewer, deep analysis
  "designer=anthropic/claude-sonnet-5:medium"  # designer; metered, so not Fable
)

# Per-agent overrides outrank frontmatter, including bundled frontmatter that
# cannot be edited here. `sonic` is documented as strictly mechanical yet ships
# at `@smol` + medium thinking; pin it to the cheapest tier at low effort.
AGENT_MODELS=(
  "sonic=openai-codex/gpt-5.6-luna:low"
)

# Read a record setting, merge KEY=VALUE pairs into it, and write it back only
# when the merge changes something. Unlisted keys in the record survive.
merge_record() {
  local key="$1"; shift
  local current merged entry
  current="$(run_omp config get "$key")"
  case "$current" in
    '{'*) ;;
    *) current='{}' ;;
  esac
  merged="$current"
  for entry in "$@"; do
    merged="$(jq -c --arg k "${entry%%=*}" --arg v "${entry#*=}" '. + {($k): $v}' <<<"$merged")"
  done
  if [ "$(jq -cS . <<<"$current")" = "$(jq -cS . <<<"$merged")" ]; then
    echo "  [model-roles] -> $agent_dir $key (ok)"
  else
    run_omp config set "$key" "$merged" >/dev/null
    echo "  [model-roles] -> $agent_dir $key ($# entries enforced)"
  fi
}

merge_record modelRoles "${ROLES[@]}"
merge_record task.agentModelOverrides "${AGENT_MODELS[@]}"
