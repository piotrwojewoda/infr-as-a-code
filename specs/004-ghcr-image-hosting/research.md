# Research: Move Image Hosting to GitHub Container Registry

**Feature**: 004-ghcr-image-hosting | **Date**: 2026-10-25

## D1 — Registry choice: GitHub Container Registry (ghcr.io)

- **Decision**: Push and pull application images from
  `ghcr.io/piotrwojewoda/<app>`.
- **Why**: the constitution already names GHCR as the registry. Hosting
  images on the Pi writes every layer twice (Kaniko cache + registry storage)
  to the SD card and keeps a 5 GiB volume busy on a device that cannot afford
  that wear. GHCR is free for this scale and stores nothing on the host.
- **Alternatives rejected**:
  - Keep the in-cluster registry: directly contradicts the reason for this
    feature.
  - Docker Hub: pull rate limits on a CI host that redeploys often; another
    account/token to manage.
  - Self-hosted registry on external storage: more moving parts than GHCR for
    a homelab.

## D2 — Authentication: existing bootstrap Secrets, mounted as files

- **Decision**: keep creating `ghcr-push` (namespace `jenkins`) and
  `ghcr-pull` (namespace `demo`) in `10-install-platform.sh`. Mount
  `ghcr-push` into the Kaniko container at `/kaniko/.docker` with the key
  `.dockerconfigjson` mapped to `config.json`. The Deployment references
  `ghcr-pull` through `imagePullSecrets`.
- **Why**: docker config JSON is exactly the format Kaniko expects. A Secret
  volume avoids putting the token into environment variables or command lines,
  so it cannot leak into logs. The bootstrap already produced these Secrets;
  no new credential flow is needed.
- **Alternatives rejected**:
  - Jenkins `withCredentials` + `docker login`: requires the Docker CLI or a
    helper inside the Kaniko image; a file mount is simpler and works with
    Kaniko's built-in config lookup.
  - Long-lived `GITHUB_TOKEN` copied into the shared library: leaks into git.
  - Public package without auth: possible, but private is the safer default
    and the pull Secret already exists.

## D3 — Token scope

- **Decision**: document and require a PAT with `read:packages`,
  `write:packages` and `repo`. The same token feeds `jenkins-github`,
  `ghcr-push` and `ghcr-pull`.
- **Why**: the previous blocker (spec 001 D2) was a token without
  `write:packages`. This feature depends on the operator supplying a token
  with that scope.
- **Failure mode**: Kaniko exits non-zero on `DENIED`; the pipeline fails
  before the GitOps bump, so the running deployment is untouched.

## D4 — Remove the old registry completely

- **Decision**: delete `clusters/malina/infrastructure/registry.yaml`, the
  apply call and the containerd `registries.yaml` block in
  `10-install-platform.sh`, and the ufw rule for `30500/tcp`. On the live
  cluster, delete the namespace and the mirror file once (documented in the
  quickstart).
- **Why**: a leftover Deployment/PVC would keep the SD card workload and an
  unnecessary port. Fresh installs must not recreate it.
- **Alternatives rejected**: keep the registry as a "warm cache" — it still
  writes layers and defeats the purpose.

## D5 — Migration order and the first image

- **Decision**: merge the platform changes and immediately trigger one
  application build. Accept a short `ImagePullBackOff` window until that
  build publishes the tag referenced by git. Then run the one-time cleanup of
  the old registry.
- **Why**: the first GHCR package version cannot exist before a build. A
  dual-push transition would add temporary code for a homelab and is not
  worth the complexity.
- **Alternatives rejected**:
  - Dual-push to both registries for one release: temporary complexity, and
    still writes to the SD card.
  - Pre-seeding GHCR manually: a manual image build outside the pipeline
    violates Constitution V; the pipeline is the only delivery path.

## D6 — Keeping the app repository unchanged

- **Decision**: the shared library owns the image reference
  (`ghcr.io/piotrwojewoda/${app}`). Application Jenkinsfiles only pass
  `app`, `testImage` and optional test settings.
- **Why**: a single place to change, and no app repo release needed for an
  infrastructure change. An app that still passes `config.registry` with the
  old value must drop that argument; the default is GHCR.
