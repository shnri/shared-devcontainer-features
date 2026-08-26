#!/usr/bin/env bash
set -euo pipefail

readonly default_max_cache_size="${DEVCONTAINER_DOCKER_STORAGE_MAX_CACHE_SIZE:-5GB}"
readonly default_unused_for="${DEVCONTAINER_DOCKER_STORAGE_UNUSED_FOR:-168h}"

usage() {
  cat <<'EOF'
Usage: devcontainer-docker-storage <status|gc> [options]

Commands:
  status  Show the Docker daemon boundary and its image, volume, and BuildKit usage.
  gc      Prune only safe, regenerable Docker resources from the selected daemon.

Options for gc:
  --max-cache-size SIZE  Cap BuildKit cache at this size (default: 5GB).
  --unused-for AGE     Remove unused devcontainer images older than AGE (default: 168h).

The selected daemon is Docker's normal CLI target. Set DOCKER_HOST or Docker context
before invoking this command when you intend to inspect a Docker-in-Docker daemon.
EOF
}

require_docker() {
  if ! command -v docker >/dev/null 2>&1; then
    echo "devcontainer-docker-storage: docker CLI was not found." >&2
    exit 127
  fi

  if ! docker info >/dev/null 2>&1; then
    echo "devcontainer-docker-storage: cannot reach the selected Docker daemon." >&2
    exit 1
  fi
}

print_daemon_boundary() {
  local docker_host="${DOCKER_HOST:-default local socket}"
  local docker_context="${DOCKER_CONTEXT:-}"

  if [[ -z "${docker_context}" ]]; then
    docker_context="$(docker context show 2>/dev/null || printf 'default')"
  fi

  printf 'Docker daemon boundary\n'
  printf '  DOCKER_HOST: %s\n' "${docker_host}"
  printf '  Docker context: %s\n' "${docker_context}"
  docker info --format '  Server: {{.ServerVersion}}\n  Docker root: {{.DockerRootDir}}\n  Daemon labels: {{json .Labels}}'
}

show_status() {
  require_docker
  print_daemon_boundary
  printf '\nDocker system usage (selected daemon)\n'
  docker system df
  printf '\nBuildKit usage (selected daemon)\n'
  if ! docker buildx du; then
    echo '  Buildx usage is unavailable for the selected daemon.' >&2
  fi
}

run_gc() {
  local max_cache_size="$1"
  local unused_for="$2"

  require_docker
  print_daemon_boundary
  printf '\nSafe Docker GC (selected daemon)\n'
  printf '  BuildKit cache maximum: %s\n' "${max_cache_size}"
  printf '  Dev Container image age threshold: %s\n' "${unused_for}"

  # Docker 29以降の--keep-storageは予約容量であり上限ではない。新しいdaemonでは
  # max-used-spaceを使い、未対応の旧daemonだけ従来optionへfallbackする。
  if docker builder prune --help 2>&1 | grep -q -- '--max-used-space'; then
    docker builder prune --all --force --max-used-space "${max_cache_size}"
  else
    docker builder prune --all --force --keep-storage "${max_cache_size}"
  fi

  # gc=ephemeralはE2Eなど、Compose側が再生成可能と明示した資産だけに付ける。
  docker container prune --force --filter 'label=gc=ephemeral'
  docker image prune --all --force --filter 'label=gc=ephemeral'
  # -a はunused named volumeも対象にするために必要。label filterが永続volumeを保護する。
  docker volume prune --all --force --filter 'label=gc=ephemeral'

  # Docker pruneはcontainerが参照するimageを削除しない。devcontainer.metadataを持つ
  # vsc-*-features等の古いFeature build imageも、現在未使用の場合だけ対象になる。
  docker image prune --all --force \
    --filter 'label=devcontainer.metadata' \
    --filter "until=${unused_for}"
}

command_name="${1:-}"
shift || true

max_cache_size="${default_max_cache_size}"
unused_for="${default_unused_for}"

case "${command_name}" in
  status)
    if [[ "$#" -ne 0 ]]; then
      usage >&2
      exit 2
    fi
    show_status
    ;;
  gc)
    while [[ "$#" -gt 0 ]]; do
      case "$1" in
        --max-cache-size)
          max_cache_size="${2:-}"
          shift 2
          ;;
        --unused-for)
          unused_for="${2:-}"
          shift 2
          ;;
        -h|--help)
          usage
          exit 0
          ;;
        *)
          echo "devcontainer-docker-storage: unknown option: $1" >&2
          usage >&2
          exit 2
          ;;
      esac
    done
    if [[ -z "${max_cache_size}" || -z "${unused_for}" ]]; then
      echo 'devcontainer-docker-storage: GC options must not be empty.' >&2
      exit 2
    fi
    run_gc "${max_cache_size}" "${unused_for}"
    ;;
  -h|--help)
    usage
    ;;
  *)
    usage >&2
    exit 2
    ;;
esac
