# Feature Specification: Move Image Hosting to GitHub Container Registry

**Feature Branch**: `004-ghcr-image-hosting`

**Created**: 2026-10-25

**Status**: Draft

**Input**: User description: "Continue this project, only change image hosting to
GitHub because hosting on the Raspberry Pi kills the SD card."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - CI publishes images to GHCR, not to the Pi (Priority: P1)

Every merge to the application repository still builds an ARM64 image with
Kaniko. This change makes Jenkins push that image to GitHub Container Registry
(`ghcr.io`) instead of the registry running on the Pi. The Pi no longer writes
multi-megabyte image layers to its SD card on every release.

**Why this priority**: SD card wear is the reason for this change. If the
pipeline still pushes to the in-cluster registry, nothing improves.

**Independent Test**: merge a change to the demo application, wait for the
Jenkins run, then look at GitHub Packages. A new `demo-symfony-k3s` package
version with both the short commit SHA tag and `latest` exists, and the Pi's
SD card did not receive a new image layer.

**Acceptance Scenarios**:

1. **Given** a merge to `main` in the application repository, **When** the
   pipeline reaches "Build & Push", **Then** Kaniko pushes
   `ghcr.io/piotrwojewoda/<app>:<short-sha>` and
   `ghcr.io/piotrwojewoda/<app>:latest` with an authenticated push.
2. **Given** a successful push, **When** the pipeline updates the GitOps
   repository, **Then** `image.tag` is bumped as before and no other file
   changes.
3. **Given** missing or insufficient GHCR credentials, **When** the pipeline
   runs, **Then** it fails at the push stage with a clear authentication error
   and the running deployment is not changed.

---

### User Story 2 - The Pi pulls private images from GHCR (Priority: P1)

The application Pod still starts after the registry switch. Because the GHCR
package is private, the Pod authenticates with the existing `ghcr-pull` Secret
that the bootstrap creates from operator input. The image never passes through
an unauthenticated registry on the LAN.

**Why this priority**: a push-only change would leave the demo app unable to
start.

**Independent Test**: after the first GHCR build, ArgoCD syncs the new
`image.tag`; the demo Pod reaches `Running`/`Ready`; `kubectl describe pod`
shows the image pulled from `ghcr.io`.

**Acceptance Scenarios**:

1. **Given** a valid `ghcr-pull` Secret in namespace `demo`, **When** the
   Deployment references `ghcr.io/piotrwojewoda/<app>:<tag>`, **Then** kubelet
   pulls the image and the Pod becomes Ready.
2. **Given** the Secret is missing or expired, **When** the Pod starts,
   **Then** it stays in `ImagePullBackOff` and the previous ReplicaSet keeps
   serving traffic (no silent downgrade).

---

### User Story 3 - The in-cluster registry is removed (Priority: P2)

The registry Deployment, PersistentVolumeClaim, Service and NodePort 30500
disappear from the platform. A freshly flashed Pi never installs them, and the
host firewall no longer allows the registry port. The stored image layers are
deleted so the SD card space and its write load are reclaimed.

**Why this priority**: leaving the old registry running would keep the fixed
5 GiB PVC, the extra container and the open node port for no benefit.

**Independent Test**: on the current cluster, `kubectl -n registry get all`
returns nothing, port 30500 is closed, and `ufw status` has no 30500 rule.
On a fresh bootstrap, no `registry` namespace is created.

**Acceptance Scenarios**:

1. **Given** this feature is applied, **When** the operator lists namespaces,
   **Then** `registry` does not exist.
2. **Given** the host firewall is active, **When** a LAN client connects to
   port 30500, **Then** the connection is refused.
3. **Given** a fresh Pi, **When** the bootstrap runs, **Then** no
   `/etc/rancher/k3s/registries.yaml` mirror for `:30500` is written and no
   registry PVC is created.

---

### Edge Cases

- The GHCR token exists but lacks `write:packages`: the push fails; docs tell
  the operator exactly which scope to add. No fallback to the old registry.
- The GHCR package is set to public by mistake: pulls still work; the
  `ghcr-pull` Secret is simply unused. The intended setting is **private**.
- First deployment after the switch: the tag in git points at an image that
  does not exist in GHCR yet. The rollout waits in `ImagePullBackOff` until
  the first pipeline run pushes that tag. Documented as a one-time migration
  window.
- GitHub is unavailable: builds fail and the Pi cannot pull uncached images,
  but already running Pods keep running (no image pull needed).
- The old `registry` namespace is deleted while ArgoCD has no app for it: no
  GitOps drift, because the registry was never an ArgoCD Application.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The pipeline MUST push each release to
  `ghcr.io/piotrwojewoda/<app>` using the short Git SHA and `latest` tags.
- **FR-002**: Push authentication MUST come from the `ghcr-push` Secret in
  namespace `jenkins`, mounted into the Kaniko container as
  `/kaniko/.docker/config.json`. No token may appear in git or in pipeline
  logs.
- **FR-003**: The application Deployment MUST pull from
  `ghcr.io/piotrwojewoda/<app>` and use the `ghcr-pull` image pull Secret.
- **FR-004**: The bootstrap script MUST keep creating `ghcr-push` and
  `ghcr-pull` from the operator's `GITHUB_TOKEN`; the token MUST have
  `read:packages` and `write:packages` (plus `repo` for the GitOps bump).
- **FR-005**: The in-cluster registry manifest
  (`clusters/malina/infrastructure/registry.yaml`) MUST be deleted, and the
  bootstrap MUST no longer apply it or write the containerd insecure-mirror
  configuration.
- **FR-006**: The host firewall MUST no longer open TCP 30500.
- **FR-007**: The chart defaults and the malina values file MUST reference
  GHCR; no `:latest` may be used as the pinned environment tag.
- **FR-008**: The pipeline MUST fail clearly when Kaniko cannot authenticate
  to GHCR; it MUST NOT silently fall back to an unauthenticated registry.
- **FR-009**: Operational documentation (README, bootstrap README, spec 001
  quickstart/research notes, spec 003 exposure contract) MUST describe GHCR
  as the only registry and include the one-time cleanup of the old registry.
- **FR-010**: A fresh Pi bootstrap plus one pipeline run MUST reproduce the
  complete chain with no registry component on the host.

### Key Entities

- **GHCR package**: `ghcr.io/piotrwojewoda/<app>`, private, ARM64, tagged by
  release SHA plus `latest`.
- **`ghcr-push` Secret** (namespace `jenkins`): docker config JSON used by
  Kaniko.
- **`ghcr-pull` Secret** (namespace `demo`): docker config JSON used by
  application Pods.
- **Removed registry stack**: namespace `registry`, Deployment `registry`,
  PVC `registry-data`, Service/NodePort 30500, containerd mirror entry.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: After the switch, a full release writes **zero** image-layer
  bytes to the Pi's SD card (verified by the absence of the registry PVC and
  of registry container logs).
- **SC-002**: A merge to `main` produces a GHCR package version and a running
  demo Pod within the existing 30-minute pipeline timeout.
- **SC-003**: Port 30500 is unreachable from the LAN and absent from
  `ufw status`.
- **SC-004**: `kubectl -n registry get all` returns "No resources found" on
  the migrated cluster.
- **SC-005**: A fresh bootstrap creates no registry workload and the demo
  deploys from GHCR on the first successful build.

## Assumptions

- The operator has a GitHub PAT (classic or fine-grained) with
  `read:packages`, `write:packages` and `repo`, and passes it as
  `GITHUB_TOKEN` to `10-install-platform.sh`.
- The GHCR package stays **private**; this is the default for a new package.
- The Raspberry Pi has working outbound internet access to `ghcr.io`.
- The demo application repository does not need code changes: the shared
  pipeline library sets the image reference. If an application Jenkinsfile
  explicitly passes the old registry through `config.registry`, that value
  must be removed.
- One short migration outage is acceptable: the first GHCR image does not
  exist until the first pipeline run after the switch.
