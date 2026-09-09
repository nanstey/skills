#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(git -C "$(dirname "${BASH_SOURCE[0]:-$PWD}")" rev-parse --show-toplevel 2>/dev/null || echo "$PWD")" && pwd)"
PI_AGENT_DIR="${PI_CODING_AGENT_DIR:-$HOME/.pi/agent}"

# Each harness declares: name | detect_dir | binaries | type:dir;type:dir;...
# A harness installs only the artifact types it lists. Add a "type:dir" pair to
# teach a harness about a new type; add a row to support a new harness.
# A dir may be a glob (e.g. one skills dir per hermes profile): it expands to
# every existing match, so a single pair can fan out to many destinations. A
# glob may sit in an interior segment (e.g. one agents dir per omp profile);
# the longest globbed prefix is expanded and the literal tail created.
HARNESSES=(
  "claude|$HOME/.claude|claude|skills:$HOME/.claude/skills;agents:$HOME/.claude/agents"
  "pi|$PI_AGENT_DIR|pi|skills:$PI_AGENT_DIR/skills;agents:$PI_AGENT_DIR/agents;config:$PI_AGENT_DIR::$REPO_ROOT/harness/pi;config:$PI_AGENT_DIR/extensions::$REPO_ROOT/harness/pi/extensions;config:$PI_AGENT_DIR/extensions/pi-interactive-subagents::$REPO_ROOT/harness/pi/extensions/pi-interactive-subagents;config:$PI_AGENT_DIR/intercom::$REPO_ROOT/harness/pi/extensions/pi-intercom;hoist:$PI_AGENT_DIR/npm::$REPO_ROOT/harness/pi/settings.json"
  "omp|$HOME/.omp/agent|omp|skills:$HOME/.omp/agent/skills;agents:$HOME/.omp/agent/agents;config:$HOME/.omp/agent::$REPO_ROOT/harness/omp;skills:$HOME/.omp/profiles/*/agent/skills;agents:$HOME/.omp/profiles/*/agent/agents;config:$HOME/.omp/profiles/*/agent::$REPO_ROOT/harness/omp;config:$PI_AGENT_DIR/intercom::$REPO_ROOT/harness/pi/extensions/pi-intercom;omp-plugin-manifest:$REPO_ROOT/harness/omp/plugins/pi-intercom.txt;omp-applicator:$REPO_ROOT/harness/omp/status-line/apply.sh;omp-applicator:$REPO_ROOT/harness/omp/model-roles/apply.sh"
  "codex|$HOME/.codex|codex|skills:$HOME/.codex/skills"
  "cursor|$HOME/.cursor|cursor,cursor-agent|skills:$HOME/.cursor/skills"
  "openclaw|$HOME/.openclaw|openclaw|skills:$HOME/.openclaw/skills"
  "hermes|$HOME/.hermes|hermes|skills:$HOME/.hermes/skills;skills:$HOME/.hermes/profiles/*/skills"
)

# Extract the `name:` value from a file's YAML frontmatter.
fm_name() {
  awk -F: '/^name:[[:space:]]*/{sub(/^name:[[:space:]]*/,"");gsub(/[[:space:]]/,"");print;exit}' "$1"
}

# Skills: directories with a SKILL.md under skills/. Emits "linkname<TAB>srcdir".
collect_skills() {
  [ -d "$REPO_ROOT/skills" ] || return 0
  # `-exec dirname` instead of GNU-only `-printf '%h\n'` so this works on BSD/macOS find too.
  find "$REPO_ROOT/skills" -type f -name SKILL.md -not -path '*/.git/*' -exec dirname {} \; | sort -u |
  while read -r d; do
    n="$(fm_name "$d/SKILL.md")"; [ -n "$n" ] || n="$(basename "$d")"
    printf '%s\t%s\n' "$n" "$(cd "$d" && pwd)"
  done
}

# Agents: *.md files under agents/. Emits "linkname.md<TAB>srcfile".
collect_agents() {
  [ -d "$REPO_ROOT/agents" ] || return 0
  find "$REPO_ROOT/agents" -type f -name '*.md' -not -path '*/.git/*' |
  while read -r f; do
    n="$(fm_name "$f")"; [ -n "$n" ] || n="$(basename "${f%.md}")"
    printf '%s.md\t%s\n' "$n" "$(cd "$(dirname "$f")" && pwd)/$(basename "$f")"
  done
}

# Config files are copied (not symlinked) because the harness may rewrite them
# locally (e.g. pi updates lastChangelogVersion). Copies the top-level files of
# src_dir into dest_dir, skipping dotfiles and subdirs. Reports ok|copy|update.
copy_one() {
  local dest="$1" src="$2"
  if [ -e "$dest" ] && cmp -s "$dest" "$src"; then echo ok
  elif [ -e "$dest" ]; then cp "$src" "$dest"; echo update
  else cp "$src" "$dest"; echo copy; fi
}

install_config() {
  local dest_dir="$1" src_dir="$2"
  if [ ! -d "$src_dir" ]; then echo "  [config] no source $src_dir, skipping"; return; fi
  mkdir -p "$dest_dir"
  local ok=0 copied=0 updated=0
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    case "$(copy_one "$dest_dir/$(basename "$f")" "$f")" in
      ok)     ok=$((ok+1)) ;;
      copy)   copied=$((copied+1)) ;;
      update) updated=$((updated+1)) ;;
    esac
  done < <(find "$src_dir" -maxdepth 1 -type f -not -name '.*')
  local summary="$ok ok"
  [ "$copied" -gt 0 ] && summary="$summary, $copied copied"
  [ "$updated" -gt 0 ] && summary="$summary, $updated updated"
  echo "  [config] -> $dest_dir ($summary)"
}

# OMP's config CLI performs schema-aware updates. Run an applicator script
# against the default config and every existing profile config. Each applicator
# owns an explicit key list and leaves every other profile-local choice, such as
# composer shape and `modelRoles.default`, untouched.
install_omp_applicator() {
  local applicator="$1" agent_dir label
  label="$(basename "$(dirname "$applicator")")"
  local -a agent_dirs=("$HOME/.omp/agent")
  if [ ! -f "$applicator" ]; then
    echo "  [$label] no source $applicator, skipping"
    return
  fi
  if [ -d "$HOME/.omp/profiles" ]; then
    shopt -s nullglob
    agent_dirs+=("$HOME"/.omp/profiles/*/agent)
    shopt -u nullglob
  fi
  for agent_dir in "${agent_dirs[@]}"; do
    [ -d "$agent_dir" ] || continue
    (cd "$REPO_ROOT" && bash "$applicator" "$agent_dir")
  done
}

# First element of settings.json's npmCommand[] (the package manager pi shells
# out to), or empty if unset. Collapses newlines so a multi-line array parses.
pi_pkg_manager() {
  [ -f "$1" ] || return 0
  tr -d '\n' <"$1" | sed -n 's/.*"npmCommand"[[:space:]]*:[[:space:]]*\[[[:space:]]*"\([^"]*\)".*/\1/p'
}

# pnpm's default isolated node_modules only exposes a package's own dependencies
# via symlinks reachable from its real path in the store. pi loads extensions
# through the top-level alias without resolving that real path, so a transitive
# dep like @shikijs/cli (a dependency of @heyhuynhgiabuu/pi-diff) is invisible
# and the extension fails with "Cannot find module". A hoisted layout puts those
# deps at the top level where they resolve through the alias too. This only
# applies to pnpm — npm/yarn/bun lay out flat already — so gate on npmCommand and
# skip otherwise. Changing the linker means the existing isolated store must be
# discarded so pnpm, which pi re-runs on launch, rebuilds it flat.
install_pnpm_hoist() {
  local npm_dir="$1" settings="$2"
  local pm; pm="$(pi_pkg_manager "$settings")"
  if [ "$pm" != "pnpm" ]; then
    echo "  [hoist] -> skip (npmCommand=${pm:-unset}, hoisting is pnpm-only)"; return
  fi
  local rc="$npm_dir/.npmrc" line="node-linker=hoisted"
  mkdir -p "$npm_dir"
  if [ -f "$rc" ] && grep -qxF "$line" "$rc"; then
    echo "  [hoist] -> $rc (ok)"; return
  fi
  printf '%s\n' "$line" >>"$rc"          # keep any other settings already present
  rm -rf "$npm_dir/node_modules" "$npm_dir/pnpm-lock.yaml"
  echo "  [hoist] -> $rc (set, store reset for flat reinstall)"
}

# Install each uncommented package specification in an OMP plugin manifest using
# OMP's native installer. The manifest is repository metadata, not runtime config.
install_omp_plugin_manifest() {
  local manifest="$1" package installed=0
  if ! command -v omp >/dev/null 2>&1; then
    echo "  [omp-plugin-manifest] omp not on PATH, skipping"
    return
  fi
  if [ ! -f "$manifest" ]; then
    echo "  [omp-plugin-manifest] no source $manifest, skipping"
    return
  fi
  while IFS= read -r package || [ -n "$package" ]; do
    package="${package#"${package%%[![:space:]]*}"}"
    package="${package%"${package##*[![:space:]]}"}"
    case "$package" in
      ''|\#*) continue ;;
    esac
    omp install "$package" || return 1
    installed=$((installed+1))
  done < "$manifest"
  echo "  [omp-plugin-manifest] -> $manifest ($installed installed)"
}

# Present if the home dir exists or any listed binary is on PATH.
present() {
  [ -d "$1" ] && return 0
  local IFS=','; for b in $2; do command -v "$b" >/dev/null 2>&1 && return 0; done
  return 1
}

# Idempotent linker shared by all types (file or directory source). Prints a
# single category word (ok|repoint|link|overwrite) so callers can tally rather
# than emit a line per artifact. The repo is the source of truth, so a real
# (non-symlink) path occupying a managed name is replaced with the symlink.
link_one() {
  local link="$1" src="$2"
  if [ -L "$link" ]; then
    if [ "$(readlink -f "$link")" = "$src" ]; then echo ok
    else ln -sfn "$src" "$link"; echo repoint; fi
  elif [ -e "$link" ]; then
    rm -rf "$link"; ln -s "$src" "$link"; echo overwrite
  else
    ln -s "$src" "$link"; echo link
  fi
}

# Expand a destination pattern into concrete directories, one per line.
# Globbing only matches paths that already exist, so a pattern whose glob sits
# in an interior segment (e.g. ~/.omp/profiles/*/agent/skills, where the leaf
# does not exist yet) would expand to nothing. Peel literal trailing segments
# off until the remaining prefix matches, then re-attach the tail; callers
# mkdir it. A literal pattern always yields itself; an unmatched glob yields
# nothing.
expand_dirs() {
  local pattern="$1" head tail m
  local -a matches
  shopt -s nullglob; matches=( $pattern ); shopt -u nullglob
  if [ "${#matches[@]}" -gt 0 ]; then printf '%s\n' "${matches[@]}"; return; fi
  case "$pattern" in
    *[*?[]*) ;;
    *) printf '%s\n' "$pattern"; return ;;
  esac
  head="$pattern"; tail=""
  while [ -n "$head" ]; do
    case "$head" in *[*?[]*) ;; *) return ;; esac
    shopt -s nullglob; matches=( $head ); shopt -u nullglob
    if [ "${#matches[@]}" -gt 0 ]; then
      for m in "${matches[@]}"; do printf '%s\n' "$m$tail"; done
      return
    fi
    tail="/${head##*/}$tail"; head="${head%/*}"
  done
}

for entry in "${HARNESSES[@]}"; do
  IFS='|' read -r name detect_dir bins typemap <<<"$entry"
  if ! present "$detect_dir" "$bins"; then echo "skip $name (not installed)"; continue; fi
  echo "== $name"
  IFS=';' read -ra pairs <<<"$typemap"
  for pair in "${pairs[@]}"; do
    type="${pair%%:*}"; pattern="${pair#*:}"
    # config pairs encode both destination and source as DEST::SRC and are
    # copied rather than symlinked, so they bypass the shared linker loop. The
    # destination may be a glob (one dir per profile).
    if [ "$type" = "config" ]; then
      while IFS= read -r dest; do
        [ -n "$dest" ] || continue
        install_config "$dest" "${pattern##*::}"
      done < <(expand_dirs "${pattern%%::*}")
      continue
    fi
    # OMP config applicators follow the config copy so they can merge their
    # managed schema keys without copying a partial config.yml into the agent dir.
    if [ "$type" = "omp-applicator" ]; then
      install_omp_applicator "$pattern"
      continue
    fi
    # hoist pairs encode NPMDIR::SETTINGS; they bypass the linker loop too.
    if [ "$type" = "hoist" ]; then
      install_pnpm_hoist "${pattern%%::*}" "${pattern##*::}"; continue
    fi
    # OMP plugin manifests are repository metadata, not copied runtime config.
    if [ "$type" = "omp-plugin-manifest" ]; then
      install_omp_plugin_manifest "$pattern"; continue
    fi
    case "$type" in
      skills) collector=collect_skills ;;
      agents) collector=collect_agents ;;
      *) echo "  [$type] unknown type, skipping"; continue ;;
    esac
    mapfile -t dirs < <(expand_dirs "$pattern")
    if [ "${#dirs[@]}" -eq 0 ]; then
      # An unmatched glob has no destination — e.g. a harness with no profiles
      # yet — so skip it rather than creating a literal `*` directory.
      echo "  [$type] no match for $pattern, skipping"; continue
    fi
    for dir in "${dirs[@]}"; do
      mkdir -p "$dir"
      ok=0; linked=0; repointed=0; overwritten=0
      while IFS=$'\t' read -r linkname src; do
        [ -n "$linkname" ] || continue
        case "$(link_one "$dir/$linkname" "$src")" in
          ok)        ok=$((ok+1)) ;;
          link)      linked=$((linked+1)) ;;
          repoint)   repointed=$((repointed+1)) ;;
          overwrite) overwritten=$((overwritten+1)) ;;
        esac
      done < <($collector)
      # One summary line per destination.
      summary="$ok ok"
      [ "$linked" -gt 0 ] && summary="$summary, $linked linked"
      [ "$repointed" -gt 0 ] && summary="$summary, $repointed repointed"
      [ "$overwritten" -gt 0 ] && summary="$summary, $overwritten overwritten"
      echo "  [$type] -> $dir ($summary)"
    done
  done
done
