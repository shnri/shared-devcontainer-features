#!/usr/bin/env bash

sync_matt_pocock_skills() {
  local install_codex="$1"
  local install_claude_code="$2"
  local -a agents=()

  if [[ "${install_codex}" == "true" ]]; then
    agents+=("codex")
  fi
  if [[ "${install_claude_code}" == "true" ]]; then
    agents+=("claude-code")
  fi

  if [[ "${#agents[@]}" -eq 0 ]]; then
    return
  fi
  if ! command -v npx >/dev/null 2>&1; then
    echo "web-dev: npx is required to synchronize Matt Pocock Skills." >&2
    return 1
  fi

  echo "web-dev: synchronizing all current Matt Pocock Skills for ${agents[*]}..."
  npx --yes skills@latest add mattpocock/skills \
    --skill '*' \
    --agent "${agents[@]}" \
    --global \
    --yes
}
