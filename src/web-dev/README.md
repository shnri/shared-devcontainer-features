# Shared Web Development (`web-dev`)

Installs the shared web development toolchain used by shnri projects.

```jsonc
"features": {
  "ghcr.io/shnri/shared-devcontainer-features/web-dev:2": {}
}
```

See the [collection README](../../README.md) for included tools, Docker storage GC opt-in, persistence behavior, version selection, and release instructions.

## Docker storage safety

The Feature installs `devcontainer-docker-storage`. It always acts on the daemon selected
by the normal Docker CLI, so `DOCKER_HOST`/Docker context distinguishes Docker-in-Docker
from the Windows Docker Desktop host daemon.

```bash
devcontainer-docker-storage status
devcontainer-docker-storage gc # BuildKit is capped at 5GB; only labelled ephemeral resources are removed
```

`postCreate` GC is opt-in because some consumers share a host daemon. A consumer with a
dedicated DinD daemon can set `runDockerStorageGcOnCreate: true`. GC caps BuildKit
cache at 5GB, removes only unused `gc=ephemeral` containers/images/named volumes,
and removes `devcontainer.metadata` images created more than seven days ago only when
they are currently unused.
It never runs an unfiltered volume prune. Consumer E2E Compose files should put
`labels: { gc: ephemeral }` on every disposable named volume and use
`docker compose down -v --remove-orphans` at the end of each run.
