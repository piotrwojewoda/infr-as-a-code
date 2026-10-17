# Implementation Plan: K3s CI/CD Platform on Raspberry Pi

**Branch**: `001-k3s-cicd-platform` | **Date**: 2026-10-17 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/001-k3s-cicd-platform/spec.md`

## Summary

Build a single-node k3s cluster on a Raspberry Pi 5 that acts as a complete
CI/CD platform. k3s (with its bundled Traefik reverse proxy on ports 80/443) is
installed by a bootstrap script. The bootstrap also installs cert-manager,
ArgoCD and Jenkins from Helm charts, with secrets created outside git. ArgoCD
then manages the demo application stack (Symfony 8 + PHP 8.5 + PostgreSQL) from
the GitOps repository `infr-as-a-code`. A merge to `main` in
`demo-symfony-k3s` triggers (by GitHub webhook) a Jenkins
pipeline that builds an ARM64 image with Kaniko, pushes it to ghcr.io, bumps the
image tag in the GitOps repository, and ArgoCD rolls it out behind
`https://demo.kreciowo.pl` with a dummy self-signed TLS certificate.

## Technical Context

**Language/Version**: YAML (Kubernetes 1.36 manifests, Helm 3.22 templates),
Groovy (Jenkinsfile, Jenkins Configuration as Code), Bash 5 (bootstrap
scripts), PHP 8.5 / Symfony 8.1 (demo application)

**Primary Dependencies**: k3s v1.36.5, Traefik (bundled with k3s), cert-manager
v1.21 (jetstack Helm chart), ArgoCD v3.5 (argo Helm chart), Jenkins LTS
(jenkinsci Helm chart + Configuration as Code plugin + Kubernetes plugin),
Kaniko v1.24 (daemonless image builds), Bitnami PostgreSQL 18 chart, GitHub
Container Registry (ghcr.io)

**Storage**: k3s `local-path-provisioner` (default StorageClass) with PVCs for
Jenkins, ArgoCD and PostgreSQL

**Testing**: smoke tests with `curl`/`kubectl` after each install step; Helm
`lint`/`template` validation for charts; one full end-to-end pipeline run
(change → merge → build → deploy → visible result)

**Target Platform**: Raspberry Pi 5, Debian 12 (bookworm), ARM64, 8 GB RAM,
node `malina` at 192.168.68.52

**Project Type**: infrastructure / platform engineering (GitOps)

**Performance Goals**: homelab scale; pipeline end-to-end under 15 minutes

**Constraints**: total workload must fit 8 GB RAM and 4 cores; all images must
support linux/arm64; inbound HTTPS to the Pi for GitHub webhooks; public git
repositories → no secrets in git

**Scale/Scope**: 1 node; namespaces: `kube-system`, `cert-manager`, `argocd`,
`jenkins`, `demo`; 3 platform hostnames; 1 demo application with 1 database

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Verdict | Evidence / Justification |
|-----------|---------|--------------------------|
| I. GitOps First | PASS (with one justified exception) | All application state is in `infr-as-a-code` and applied by ArgoCD. Exception: cert-manager, ArgoCD and Jenkins themselves are installed by documented bootstrap scripts (`clusters/malina/bootstrap/`), because ArgoCD cannot install itself and Jenkins must exist before the first pipeline runs. The scripts are code in git, so the rule "no undocumented manual change" still holds. |
| II. Infrastructure as Code | PASS | Every install step is a script or chart values file in git. |
| III. No Secrets in Git | PASS | GitHub PAT, DB password and admin passwords are created as Kubernetes Secrets by the bootstrap script (from operator input), never committed. Git holds only secret *names*. |
| IV. Simplicity First | PASS | Uses k3s-bundled Traefik and local-path storage instead of extra components. One node, five namespaces, four Helm releases total. |
| V. Automated Delivery | PASS | Jenkins + ArgoCD pipeline defined in code; demo app cannot be deployed by hand (no other path exists). |

Post-design re-check: passed (see research.md decisions D1–D8).

## Project Structure

### Documentation (this feature)

```text
specs/001-k3s-cicd-platform/
├── plan.md              # This file
├── research.md          # Phase 0: technology decisions D1–D8
├── data-model.md        # Phase 1: configuration schema / entities
├── quickstart.md        # Phase 1: bootstrap + daily use runbook
├── contracts/           # Phase 1: interfaces between components
│   ├── pipeline.md      # Jenkins pipeline contract
│   ├── gitops.md        # ArgoCD application contracts
│   └── ingress.md       # hostname → service → TLS mapping
└── tasks.md             # Phase 2 output (/speckit.tasks)
```

### Source Code (repository root = `infr-as-a-code`)

```text
.
├── .opencode/commands/          # Spec Kit slash commands (skills)
├── .specify/                    # Spec Kit memory, templates, scripts
├── specs/                       # Feature specifications (this one included)
├── clusters/
│   └── malina/                  # Cluster-specific configuration
│       ├── bootstrap/
│       │   ├── 00-install-k3s.sh
│       │   ├── 10-install-platform.sh   # cert-manager, ArgoCD, Jenkins
│       │   ├── jenkins-values.yaml      # Jenkins Helm values (JCasC, no secrets)
│       │   ├── argocd-values.yaml
│       │   └── README.md
│       ├── infrastructure/
│       │   ├── cluster-issuers.yaml     # selfsigned (dummy) + letsencrypt (ready)
│       │   └── certificates.yaml        # dummy TLS certs per namespace
│       ├── apps/
│       │   ├── root-app.yaml            # ArgoCD app-of-apps entrypoint
│       │   ├── demo-postgres.yaml       # PostgreSQL (Bitnami chart)
│       │   └── demo-symfony.yaml        # demo app (multi-source: chart + values)
│       └── values/
│           └── demo-symfony.yaml        # env values; image.tag bumped by Jenkins
├── charts/
│   └── demo-symfony/            # Helm chart for the demo application
│       ├── Chart.yaml
│       ├── values.yaml
│       └── templates/           # deployment, service, ingress, hpa-less, probes
└── README.md
```

The application repository `demo-symfony-k3s` (separate) holds: Symfony source,
`Dockerfile`, `.dockerignore`, `Jenkinsfile`, `README.md`.

## Phase Outputs

- Phase 0 → [research.md](./research.md) — decisions D1–D8 with alternatives.
- Phase 1 → [data-model.md](./data-model.md), [contracts/](./contracts),
  [quickstart.md](./quickstart.md).
- Phase 2 → tasks.md (created by `/speckit.tasks`).
