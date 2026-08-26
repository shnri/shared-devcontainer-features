#!/usr/bin/env bash
set -euo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
test_root="$(mktemp -d)"
readonly repository_root test_root
readonly fake_bin="${test_root}/bin"
readonly docker_log="${test_root}/docker.log"

cleanup() {
  rm -rf -- "${test_root}"
}
trap cleanup EXIT

mkdir -p "${fake_bin}"
cat > "${fake_bin}/docker" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

printf '%q ' "$@" >> "${FAKE_DOCKER_LOG}"
printf '\n' >> "${FAKE_DOCKER_LOG}"

case "$1 ${2:-}" in
  'info '|'info --format')
    if [[ "${2:-}" == '--format' ]]; then
      printf '  Server: fake\n  Docker root: /var/lib/docker\n  Daemon labels: {"daemon":"dind"}\n'
    fi
    ;;
  'context show')
    printf 'fake-context\n'
    ;;
  'system df')
    printf 'TYPE TOTAL ACTIVE SIZE RECLAIMABLE\n'
    ;;
  'buildx du')
    printf 'ID RECLAIMABLE\n'
    ;;
  'builder prune')
    if [[ " ${*} " == *' --help '* ]]; then
      printf '      --max-used-space bytes\n'
    fi
    ;;
esac
EOF
chmod 0755 "${fake_bin}/docker"

fail() {
  echo "docker-storage test failed: $*" >&2
  exit 1
}

assert_log_contains() {
  local expected="$1"
  grep -Fq -- "${expected}" "${docker_log}" || fail "missing docker command: ${expected}"
}

env PATH="${fake_bin}:${PATH}" \
  FAKE_DOCKER_LOG="${docker_log}" \
  DOCKER_HOST='tcp://dind:2375' \
  bash "${repository_root}/src/web-dev/docker-storage.sh" status > "${test_root}/status"

grep -Fq 'DOCKER_HOST: tcp://dind:2375' "${test_root}/status" ||
  fail 'status did not identify the selected Docker daemon'
grep -Fq 'Daemon labels: {"daemon":"dind"}' "${test_root}/status" ||
  fail 'status did not include daemon labels'
assert_log_contains 'system df '
assert_log_contains 'buildx du '

: > "${docker_log}"
env PATH="${fake_bin}:${PATH}" \
  FAKE_DOCKER_LOG="${docker_log}" \
  bash "${repository_root}/src/web-dev/docker-storage.sh" gc \
  --max-cache-size 4GB --unused-for 72h > /dev/null

assert_log_contains 'builder prune --help '
assert_log_contains 'builder prune --all --force --max-used-space 4GB '
assert_log_contains 'container prune --force --filter label=gc=ephemeral '
assert_log_contains 'image prune --all --force --filter label=gc=ephemeral '
assert_log_contains 'volume prune --all --force --filter label=gc=ephemeral '
assert_log_contains 'image prune --all --force --filter label=devcontainer.metadata --filter until=72h '

if grep -Fq 'volume prune --all --force ' "${docker_log}" &&
  ! grep -Fq 'volume prune --all --force --filter label=gc=ephemeral ' "${docker_log}"; then
  fail 'named volume prune was not constrained by gc=ephemeral'
fi

echo 'Docker storage CLI tests passed.'
