#!/usr/bin/env bash
# 旧versionのweb-devが配置したshared-agent-plugins由来のglobal instructionsを片付ける。
# 常時指示の原本と配置はagent-config repositoryへ移ったため、このFeatureは書き込まず、
# 自身が所有していた痕跡だけを取り除く。所有外の内容や不明なfileには触れない。

readonly shared_instructions_begin='<!-- shared-agent-plugins:global-instructions:start -->'
readonly shared_instructions_end='<!-- shared-agent-plugins:global-instructions:end -->'

remove_codex_shared_instructions() {
  local codex_home="$1"
  local target_path="${codex_home}/AGENTS.md"
  local begin_count=0
  local end_count=0
  local output_path=""

  [[ -e "${target_path}" || -L "${target_path}" ]] || return 0
  if [[ -L "${target_path}" || ! -f "${target_path}" ]]; then
    echo "web-dev: refusing to clean unsafe Codex instructions at ${target_path}." >&2
    return 1
  fi
  begin_count="$(grep -Fxc -- "${shared_instructions_begin}" "${target_path}" || true)"
  end_count="$(grep -Fxc -- "${shared_instructions_end}" "${target_path}" || true)"
  if [[ "${begin_count}" == "0" && "${end_count}" == "0" ]]; then
    return 0
  fi
  if [[ "${begin_count}" != "1" || "${end_count}" != "1" ]]; then
    echo "web-dev: refusing to clean malformed shared instructions in ${target_path}." >&2
    return 1
  fi

  output_path="$(mktemp "${codex_home}/.AGENTS.md.XXXXXX")"
  # blockの直前にinstallerが入れた空行ごと取り除く。
  if ! awk \
    -v begin="${shared_instructions_begin}" \
    -v end="${shared_instructions_end}" '
      $0 == begin { inside = 1; pending_blank = 0; next }
      inside && $0 == end { inside = 0; next }
      inside { next }
      $0 == "" { pending_blank++; next }
      { for (i = 0; i < pending_blank; i++) print ""; pending_blank = 0; print }
      END { if (inside) exit 2 }
    ' "${target_path}" > "${output_path}"; then
    rm -f -- "${output_path}"
    echo "web-dev: refusing to clean malformed shared instructions in ${target_path}." >&2
    return 1
  fi

  if [[ ! -s "${output_path}" ]]; then
    rm -f -- "${output_path}" "${target_path}"
    echo "web-dev: removed legacy shared instructions file ${target_path}."
    return 0
  fi
  chmod --reference="${target_path}" "${output_path}"
  mv -- "${output_path}" "${target_path}"
  echo "web-dev: removed legacy shared instructions block from ${target_path}."
}

validate_claude_owned_rules() {
  local owned_root="$1"
  local entry=""
  local name=""

  if [[ -L "${owned_root}" ]]; then
    echo "web-dev: refusing to remove symlinked Claude rules at ${owned_root}." >&2
    return 1
  fi
  [[ -d "${owned_root}" ]] || return 0

  while IFS= read -r -d '' entry; do
    name="$(basename "${entry}")"
    case "${name}" in
      common.md|claude.md|.source.json) ;;
      *)
        echo "web-dev: refusing to remove unknown Claude rule entry ${entry}." >&2
        return 1
        ;;
    esac
    if [[ -L "${entry}" || ! -f "${entry}" ]]; then
      echo "web-dev: refusing to remove unsafe Claude rule entry ${entry}." >&2
      return 1
    fi
  done < <(find "${owned_root}" -mindepth 1 -maxdepth 1 -print0)
}

remove_claude_shared_instructions() {
  local claude_home="$1"
  local owned_root="${claude_home}/rules/shared-agent-plugins"

  [[ -e "${owned_root}" || -L "${owned_root}" ]] || return 0
  validate_claude_owned_rules "${owned_root}" || return 1
  rm -rf -- "${owned_root}"
  echo "web-dev: removed legacy shared instructions directory ${owned_root}."
}

remove_shared_global_instructions() {
  local codex_home="$1"
  local claude_home="$2"
  local clean_codex="$3"
  local clean_claude="$4"

  if [[ "${clean_codex}" == "true" ]]; then
    remove_codex_shared_instructions "${codex_home}"
  fi
  if [[ "${clean_claude}" == "true" ]]; then
    remove_claude_shared_instructions "${claude_home}"
  fi
}
