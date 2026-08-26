#!/usr/bin/env bash

readonly shared_instructions_begin='<!-- shared-agent-plugins:global-instructions:start -->'
readonly shared_instructions_end='<!-- shared-agent-plugins:global-instructions:end -->'

shared_instruction_hash() {
  sha256sum "$1" | awk '{ print $1 }'
}

render_shared_fragment() {
  local name="$1"
  local source_path="$2"
  local source_ref="$3"
  local source_commit="$4"
  local content_hash=""

  content_hash="$(shared_instruction_hash "${source_path}")"
  printf '<!-- generated from shared-agent-plugins %s (%s); %s sha256:%s -->\n' \
    "${source_ref}" "${source_commit}" "${name}" "${content_hash}"
  cat -- "${source_path}"
}

render_codex_shared_instructions() {
  local source_root="$1"
  local source_ref="$2"
  local source_commit="$3"

  printf '%s\n' "${shared_instructions_begin}"
  render_shared_fragment \
    common "${source_root}/common.md" "${source_ref}" "${source_commit}"
  printf '\n'
  render_shared_fragment \
    codex "${source_root}/codex.md" "${source_ref}" "${source_commit}"
  printf '%s\n' "${shared_instructions_end}"
}

install_codex_shared_instructions() {
  local source_root="$1"
  local source_ref="$2"
  local source_commit="$3"
  local codex_home="$4"
  local target_path="${codex_home}/AGENTS.md"
  local begin_count=0
  local end_count=0
  local block_path=""
  local output_path=""

  mkdir -p -- "${codex_home}"
  if [[ -L "${target_path}" || ( -e "${target_path}" && ! -f "${target_path}" ) ]]; then
    echo "web-dev: refusing to update unsafe Codex instructions at ${target_path}." >&2
    return 1
  fi
  touch -- "${target_path}"
  begin_count="$(grep -Fxc -- "${shared_instructions_begin}" "${target_path}" || true)"
  end_count="$(grep -Fxc -- "${shared_instructions_end}" "${target_path}" || true)"
  if ! { [[ "${begin_count}" == "0" && "${end_count}" == "0" ]] ||
    [[ "${begin_count}" == "1" && "${end_count}" == "1" ]]; }; then
    echo "web-dev: refusing to update malformed shared instructions in ${target_path}." >&2
    return 1
  fi

  block_path="$(mktemp "${codex_home}/.shared-instructions-block.XXXXXX")"
  output_path="$(mktemp "${codex_home}/.AGENTS.md.XXXXXX")"
  render_codex_shared_instructions \
    "${source_root}" "${source_ref}" "${source_commit}" > "${block_path}"

  if [[ "${begin_count}" == "0" ]]; then
    cat -- "${target_path}" > "${output_path}"
    if [[ -s "${target_path}" ]]; then
      printf '\n' >> "${output_path}"
    fi
    cat -- "${block_path}" >> "${output_path}"
  elif ! awk \
    -v begin="${shared_instructions_begin}" \
    -v end="${shared_instructions_end}" \
    -v block_path="${block_path}" '
      $0 == begin {
        while ((getline line < block_path) > 0) print line
        close(block_path)
        inside = 1
        next
      }
      inside && $0 == end {
        inside = 0
        next
      }
      !inside { print }
      END { if (inside) exit 2 }
    ' "${target_path}" > "${output_path}"; then
    rm -f -- "${block_path}" "${output_path}"
    echo "web-dev: refusing to update malformed shared instructions in ${target_path}." >&2
    return 1
  fi

  chmod --reference="${target_path}" "${output_path}"
  if cmp -s -- "${target_path}" "${output_path}"; then
    rm -f -- "${output_path}"
  else
    mv -- "${output_path}" "${target_path}"
  fi
  rm -f -- "${block_path}"
}

validate_claude_owned_rules() {
  local owned_root="$1"
  local entry=""
  local name=""

  if [[ -L "${owned_root}" ]]; then
    echo "web-dev: refusing to replace symlinked Claude rules at ${owned_root}." >&2
    return 1
  fi
  [[ -d "${owned_root}" ]] || return 0

  while IFS= read -r -d '' entry; do
    name="$(basename "${entry}")"
    case "${name}" in
      common.md|claude.md|.source.json) ;;
      *)
        echo "web-dev: refusing to replace unknown Claude rule entry ${entry}." >&2
        return 1
        ;;
    esac
    if [[ -L "${entry}" || ! -f "${entry}" ]]; then
      echo "web-dev: refusing to replace unsafe Claude rule entry ${entry}." >&2
      return 1
    fi
  done < <(find "${owned_root}" -mindepth 1 -maxdepth 1 -print0)
}

install_claude_shared_instructions() {
  local source_root="$1"
  local source_ref="$2"
  local source_commit="$3"
  local claude_home="$4"
  local rules_parent="${claude_home}/rules"
  local owned_root="${rules_parent}/shared-agent-plugins"
  local stage_root=""
  local backup_root="${rules_parent}/.shared-agent-plugins.backup.$$"
  local common_hash=""
  local claude_hash=""

  mkdir -p -- "${rules_parent}"
  validate_claude_owned_rules "${owned_root}" || return 1
  if [[ -e "${backup_root}" || -L "${backup_root}" ]]; then
    echo "web-dev: refusing to overwrite existing Claude rules backup ${backup_root}." >&2
    return 1
  fi

  stage_root="$(mktemp -d "${rules_parent}/.shared-agent-plugins.XXXXXX")"
  render_shared_fragment \
    common "${source_root}/common.md" "${source_ref}" "${source_commit}" \
    > "${stage_root}/common.md"
  render_shared_fragment \
    claude "${source_root}/claude.md" "${source_ref}" "${source_commit}" \
    > "${stage_root}/claude.md"
  common_hash="$(shared_instruction_hash "${source_root}/common.md")"
  claude_hash="$(shared_instruction_hash "${source_root}/claude.md")"
  printf '{\n  "sourceRef": "%s",\n  "sourceCommit": "%s",\n  "hashes": {\n    "common": "%s",\n    "claude": "%s"\n  }\n}\n' \
    "${source_ref}" "${source_commit}" "${common_hash}" "${claude_hash}" \
    > "${stage_root}/.source.json"

  if [[ -d "${owned_root}" ]] && diff -qr -- "${owned_root}" "${stage_root}" >/dev/null; then
    rm -rf -- "${stage_root}"
    return 0
  fi

  if [[ -d "${owned_root}" ]]; then
    mv -- "${owned_root}" "${backup_root}"
  fi
  if ! mv -- "${stage_root}" "${owned_root}"; then
    [[ -d "${backup_root}" ]] && mv -- "${backup_root}" "${owned_root}"
    return 1
  fi
  if [[ -d "${backup_root}" ]]; then
    rm -rf -- "${backup_root}"
  fi
}

install_shared_global_instructions() {
  local checkout_root="$1"
  local source_ref="$2"
  local source_commit="$3"
  local codex_home="$4"
  local claude_home="$5"
  local install_codex="$6"
  local install_claude="$7"
  local source_root="${checkout_root}/global-instructions"

  if [[ ! -f "${source_root}/common.md" ||
    ! -f "${source_root}/claude.md" ||
    ! -f "${source_root}/codex.md" ]]; then
    echo "web-dev: pinned shared-agent-plugins release has no global instructions; skipping." >&2
    return 0
  fi

  if [[ "${install_codex}" == "true" ]]; then
    install_codex_shared_instructions \
      "${source_root}" "${source_ref}" "${source_commit}" "${codex_home}"
  fi
  if [[ "${install_claude}" == "true" ]]; then
    install_claude_shared_instructions \
      "${source_root}" "${source_ref}" "${source_commit}" "${claude_home}"
  fi
}
