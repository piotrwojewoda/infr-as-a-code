# Contract: Image Registry (GHCR)

**Feature**: 004-ghcr-image-hosting | **Date**: 2026-10-25

This contract is binding for every application built by the malina platform.

## 1. Image reference

| Item | Value |
|------|-------|
| Registry | `ghcr.io` |
| Namespace (owner) | `piotrwojewoda` |
| Repository | `<app>` (same value as `config.app`) |
| Tags | `<short-git-sha>` (immutable), `latest` (convenience) |
| Platform | `linux/arm64` only |
| Visibility | private |

Full reference: `ghcr.io/piotrwojewoda/<app>:<tag>`.

## 2. Push (pipeline)

- Kaniko runs `--context`, `--dockerfile`, and two `--destination` flags. It
  MUST NOT use `--insecure`.
- Authentication: the `ghcr-push` Secret in namespace `jenkins` is mounted at
  `/kaniko/.docker` with `items: [{key: .dockerconfigjson, path: config.json}]`.
- Required token scope: `write:packages` (+ `read:packages`, `repo`).
- A failed push MUST fail the pipeline before the "Update GitOps" stage, so
  the running deployment is not touched.

## 3. Pull (cluster)

- `clusters/malina/values/<app>.yaml` MUST set:
  - `image.repository: ghcr.io/piotrwojewoda/<app>`
  - `imagePullSecrets: [{ name: ghcr-pull }]`
- The `ghcr-pull` Secret is created by `10-install-platform.sh` in the
  application namespace (`demo` for the current app).
- `image.tag` MUST be a release SHA, never `latest`.

## 4. Bootstrap

`10-install-platform.sh` creates both GHCR Secrets from `GITHUB_USER` +
`GITHUB_TOKEN` (input only, never in git). It MUST NOT install a local
registry, write a containerd insecure mirror, or open TCP 30500.

## 5. Fresh-install guarantee

After `00-install-k3s.sh` → `05-hardening.sh` → `10-install-platform.sh`:

- no `registry` namespace, Deployment, PVC or Service exists;
- `ufw status` has no 30500 rule;
- `/etc/rancher/k3s/registries.yaml` has no `:30500` mirror;
- the first successful pipeline run publishes to GHCR and the demo Pod
  pulls from `ghcr.io`.
