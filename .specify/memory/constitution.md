# Malina K3s CI/CD Platform Constitution

## Core Principles

### I. GitOps First (NON-NEGOTIABLE)

Every change to the cluster MUST be a commit in the `infr-as-a-code` repository.
ArgoCD reads that repository and applies the change. Nobody may run `kubectl` or
`helm` to change the cluster by hand. The only allowed manual steps are the
bootstrap scripts stored in this repository.

Rationale: if the cluster is lost, one bootstrap run plus one ArgoCD sync MUST
rebuild everything. This is only possible when git is the single source of truth.

### II. Infrastructure as Code

Every part of the platform MUST exist as code in git: install scripts, Helm
charts, Kubernetes manifests, CI/CD pipeline definitions. Documentation alone is
not enough. A new person MUST be able to rebuild the platform from the
repository without private knowledge.

### III. No Secrets in Git (NON-NEGOTIABLE)

Passwords, tokens and certificates keys MUST NOT be committed to git. Secrets
live only in Kubernetes Secret objects created by bootstrap scripts or by the
operator. Git may hold placeholders or references to secret names only.

Rationale: the repositories are public on GitHub. One leaked token in git
history is a permanent leak.

### IV. Simplicity First (KISS)

The platform runs on ONE Raspberry Pi with 8 GB RAM. Every added component MUST
have a clear reason to exist. Prefer the tool that is already installed (k3s
bundled Traefik) over a new tool. Reject complexity that a homelab does not
need. Resource requests and limits MUST fit the hardware.

### V. Automated Delivery

Every application on the cluster MUST build and deploy through the pipeline:
a merge to `main` on GitHub triggers Jenkins, Jenkins builds and pushes an
image, updates the GitOps repository, and ArgoCD deploys it. No application may
be deployed by hand. Helm charts are the packaging format for all applications.

## Technology Constraints

- Cluster: k3s (single server node) on Raspberry Pi 5, Debian 12, ARM64.
- Package format: Helm 3 charts for every deployable component.
- Ingress: Traefik (bundled with k3s), ports 80 and 443 exposed on the node.
- TLS: cert-manager issues certificates; a self-signed dummy certificate is
  used until the operator installs the real certificate for `kreciowo.pl`.
- CI: Jenkins on the cluster; CD: ArgoCD on the cluster.
- Image registry: GitHub Container Registry (ghcr.io).
- All container images MUST support `linux/arm64`.
- Application stack for the demo: Symfony 8 on PHP 8.5 with PostgreSQL.

## Development Workflow

1. Work is specified first: every feature starts from a Spec Kit specification
   in `specs/`, then a plan, then tasks, then implementation.
2. Application code lives in its own repository (example:
   `demo-symfony-k3s`). Cluster and platform code lives in `infr-as-a-code`.
3. A merge to `main` is the only event that builds and deploys an application.
4. Changes to the platform are merged to `main` of `infr-as-a-code`; ArgoCD
   applies them automatically.
5. Spec Kit artifacts (constitution, specs) are part of this repository and are
   updated when the platform changes direction.

## Governance

- This constitution supersedes other habits and preferences.
- Amendments need a commit that changes this file, a version bump and a short
  reason in the commit message.
- Versioning: MAJOR for removed or redefined principles, MINOR for new
  principles or sections, PATCH for wording fixes.
- Every plan and every pull request MUST be checked against these principles.
  A violation must be justified in writing or the change is rejected.

**Version**: 1.0.0 | **Ratified**: 2026-10-17 | **Last Amended**: 2026-10-17
