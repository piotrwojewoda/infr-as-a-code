# Implementation Plan: Move Image Hosting to GitHub Container Registry

**Branch**: `004-ghcr-image-hosting` | **Date**: 2026-10-25 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/004-ghcr-image-hosting/spec.md`

## Summary

Replace the in-cluster `registry:2` running on the Pi with GitHub Container
Registry. Jenkins/Kaniko keeps building ARM64 images, but pushes them to
`ghcr.io/piotrwojewoda/<app>` using the already-created `ghcr-push` Secret.
The demo Deployment pulls the private package with the existing `ghcr-pull`
Secret. The registry Deployment/PVC/NodePort, the containerd insecure mirror
and the firewall rule for port 30500 are removed. Net effect: releases stop
writing image layers to the SD card, while the GitOps flow (test → build →
push → tag bump → ArgoCD rollout) stays exactly the same.

## Technical Context

**Language/Version**: Groovy (Jenkins shared library), Bash 5 (bootstrap),
YAML (Helm values, Kubernetes manifests, pod template)

**Primary Dependencies**: Kaniko v1.24.0-debug, GitHub Container Registry
(`ghcr.io`), Kubernetes docker-registry Secrets, k3s containerd, Traefik
(unchanged), ArgoCD (unchanged)

**Storage**: No local image storage anymore. Remove the 5 GiB
`registry-data` PVC. GHCR stores the images remotely.

**Testing**: `helm template` + `kubectl apply --dry-run=client` for manifests;
one real pipeline run; `kubectl -n demo describe pod` for the pull secret;
`kubectl -n registry get all`; `ufw status`; LAN probe of port 30500.

**Target Platform**: Raspberry Pi 5, Debian 12, k3s, ARM64; Kaniko and images
must stay `linux/arm64`.

**Project Type**: infrastructure / CI-CD platform change (GitOps)

**Performance Goals**: release time unchanged (GitHub upload instead of LAN
push); SD card writes during a release drop to zero image bytes.

**Constraints**: no secrets in git (Constitution III); no manual cluster
mutations outside the documented migration (Constitution I); no new cluster
component (Constitution IV — GHCR is external); pipeline remains the only
delivery path (Constitution V).

**Scale/Scope**: 1 shared-library file, 1 bootstrap script, 1 values file,
1 fleet of docs; delete 1 manifest. No application code changes.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Verdict | Evidence / Justification |
|-----------|---------|--------------------------|
| I. GitOps First | PASS | Every change is a commit in this repository or in the pipeline library; the one-time registry cleanup is documented as an operator step because the old registry was never an ArgoCD Application. |
| II. Infrastructure as Code | PASS | Registry choice is code (pipeline default, values, bootstrap, manifests). Rebuild from zero creates no registry. |
| III. No Secrets in Git | PASS | Tokens stay in bootstrap-created Secrets; only Secret names and mounting paths are in git. |
| IV. Simplicity First | PASS | Removes a component (registry container, PVC, node port, containerd mirror) and moves storage to an external managed service. This is simpler than the current setup. |
| V. Automated Delivery | PASS | Same pipeline stages and test gate; only the destination of the push changes. |

Post-design re-check: passed (see research.md D1–D5).

## Project Structure

### Documentation (this feature)

```text
specs/004-ghcr-image-hosting/
├── plan.md              # This file
├── research.md          # Phase 0: decisions D1–D5
├── data-model.md        # Phase 1: registry/secret/image entities
├── quickstart.md        # Phase 1: migration + validation runbook
├── contracts/
│   └── registry.md      # push/pull/auth contract
└── tasks.md             # Phase 2 output (/speckit.tasks)
```

### Source Code (repository root = `infr-as-a-code`)

```text
.
├── jenkins/shared-library/vars/ciPipeline.groovy  # default registry -> ghcr.io,
│                                                  # mount ghcr-push, drop --insecure
├── clusters/malina/
│   ├── bootstrap/
│   │   ├── 05-hardening.sh            # remove ufw rule for 30500
│   │   ├── 10-install-platform.sh     # remove registry apply + mirror block
│   │   └── README.md                  # GHCR-only bootstrap notes
│   ├── values/demo-symfony.yaml       # ghcr.io repo + ghcr-pull secret
│   └── infrastructure/registry.yaml   # DELETED
├── charts/demo-symfony/
│   ├── Chart.yaml                     # version bump (documentation of change)
│   └── values.yaml                    # GHCR defaults (already present, verify)
├── README.md                          # GHCR as the only registry
└── specs/                             # 001/003 current-state notes updated;
                                       # 004 is the source of truth
```

**Structure Decision**: no new directories or components. The change edits the
existing pipeline library, bootstrap scripts and values, deletes the old
registry manifest, and records the decision in this spec.

## Complexity Tracking

No constitution violations → no justifications required.

## Phase Outputs

- Phase 0 → [research.md](./research.md) — decisions D1–D5 with alternatives.
- Phase 1 → [data-model.md](./data-model.md),
  [contracts/registry.md](./contracts/registry.md),
  [quickstart.md](./quickstart.md).
- Phase 2 → tasks.md (created by `/speckit.tasks`).
