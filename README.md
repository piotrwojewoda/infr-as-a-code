# infr-as-a-code — Malina K3s CI/CD Platform

GitOps repository for a single-node **k3s** cluster on a Raspberry Pi 5
(`malina`, 192.168.68.52) that works as a complete CI/CD platform:

- **CI**: Jenkins (Kubernetes agents + Kaniko builds) → pushes images to
  GitHub Container Registry (`ghcr.io/piotrwojewoda/<app>`, private; spec 004)
- **CD**: ArgoCD (app-of-apps) applies everything from this repository
- **Ingress**: Traefik (bundled with k3s) on ports 80/443
- **TLS**: cert-manager — dummy self-signed certificate now, real one later
- **Demo app**: Symfony 8 + PHP 8.5 + PostgreSQL at `https://kreciowo.pl`
  (real cert; tools: `kreciowo.pl/jenkins/`, `kreciowo.pl/argocd/`;
  source: `piotrwojewoda/demo-symfony-k3s`)
- **Management**: Rancher at `https://rancher.kreciowo.pl` (LAN only)
- **Load testing**: on-demand kube-burner Jobs for Kubernetes API, scheduler
  and bounded CPU load (disabled by default; spec 009)

A merge to `main` of an application repository triggers the full chain via a
GitHub webhook → build → push image to GHCR → bump `image.tag` here → ArgoCD
rollout. No image data is stored on the Pi's SD card.

## Layout

```text
.specify/                      Spec Kit (constitution, templates, scripts)
.opencode/commands/            Spec Kit slash commands (skills) for OpenCode
specs/001-k3s-cicd-platform/   Full specification, plan, contracts, tasks
clusters/malina/
├── bootstrap/                 One-time install scripts (k3s, platform)
├── infrastructure/            ClusterIssuers, dummy certs, Traefik config
├── apps/                      ArgoCD Applications (root-app = entrypoint)
└── values/                    Per-cluster values (image.tag bumped by CI)
charts/demo-symfony/           Helm chart for the demo application
charts/kube-burner/            Opt-in cluster load-test chart (spec 009)
charts/monitoring/             Prometheus + Grafana umbrella chart
specs/009-rancher-load-testing/ Rancher and load-test specification/runbook
```

## Quickstart

See [specs/001-k3s-cicd-platform/quickstart.md](specs/001-k3s-cicd-platform/quickstart.md)
for bootstrap, daily use, password retrieval and the dummy→real certificate
swap.

## Rules (Constitution, short version)

1. **GitOps first** — every cluster change is a commit here; ArgoCD applies it.
2. **Everything as code** — scripts, charts, manifests; no manual installs.
3. **No secrets in git** — ever. Secrets are created by bootstrap scripts.
4. **KISS** — one Pi, minimal components, every component justified.
5. **Automated delivery** — applications deploy only through the pipeline.

Full text: [.specify/memory/constitution.md](.specify/memory/constitution.md)

## Spec Kit

This repository uses [GitHub Spec Kit](https://github.com/github/spec-kit)
(spec-driven development). Slash commands (skills) are installed for OpenCode
in `.opencode/commands/`: `/speckit.constitution`, `/speckit.specify`,
`/speckit.plan`, `/speckit.tasks`, `/speckit.implement`, `/speckit.analyze`,
`/speckit.clarify`, `/speckit.checklist`, `/speckit.converge`,
`/speckit.taskstoissues`.
