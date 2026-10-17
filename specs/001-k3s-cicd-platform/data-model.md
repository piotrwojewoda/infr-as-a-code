# Phase 1 Data Model: Configuration Schema

**Feature**: 001-k3s-cicd-platform | **Date**: 2026-10-17

This platform has no business database. Its "data" is configuration. The
entities below are Kubernetes/Helm objects and the files that describe them.

## Entity: Release (the thing the pipeline produces)

| Field | Type | Source of truth | Notes |
|-------|------|-----------------|-------|
| `image.repository` | string | `clusters/malina/values/demo-symfony.yaml` | fixed: `192.168.68.52:30500/demo-symfony-k3s` (in-cluster registry, see research.md D2) |
| `image.tag` | string | same file, **written by Jenkins** | short git SHA of the app repo, e.g. `a1b2c3d`; `latest` is also pushed but never used by deployments |
| `image.pullPolicy` | string | chart default | `IfNotPresent` |

State flow: `merge on main` → Jenkins builds image `:sha` → Jenkins commits new
`image.tag` to the GitOps repo → ArgoCD syncs → Deployment rolls to `:sha`.

## Entity: ArgoCD Application (desired state per component)

| Field | Meaning |
|-------|---------|
| `metadata.name` | component name (`demo-postgres`, `demo-symfony`) |
| `spec.source(s)` | Helm chart location (repoURL + path or chart name + version) |
| `spec.destination` | cluster + namespace (`demo`) |
| `spec.syncPolicy.automated` | `prune: true`, `selfHeal: true` — drift is corrected |

## Entity: Secret (never in git)

| Name | Namespace | Keys | Created by | Used by |
|------|-----------|------|------------|---------|
| `ghcr-pull` | `demo` | `.dockerconfigjson` | bootstrap script | (dormant — for the future GHCR swap; in-cluster registry needs no auth) |
| `demo-db` | `demo` | `password`, `postgres-password` | bootstrap script | PostgreSQL (Bitnami `auth.existingSecret`) |
| `demo-app` | `demo` | `DATABASE_URL`, `APP_SECRET` | bootstrap script | demo app Deployment env |
| `jenkins-github` | `jenkins` | `username`, `token` | bootstrap script | JCasC credential → pipeline pushes GitOps tag bump |
| `argocd-initial-admin` | `argocd` | `password` | ArgoCD install | first login (runbook: change it) |

## Entity: Hostname routing (see contracts/ingress.md)

| Hostname | Namespace | Service | TLS secret |
|----------|-----------|---------|------------|
| `demo.kreciowo.pl` | `demo` | `demo-symfony:80` | `kreciowo-dummy-tls` |
| `jenkins.kreciowo.pl` | `jenkins` | `jenkins:8080` | `kreciowo-dummy-tls` |
| `argocd.kreciowo.pl` | `argocd` | `argocd-server:80` | `kreciowo-dummy-tls` |

## Entity: Environment values file (`clusters/malina/values/demo-symfony.yaml`)

```yaml
image:
  repository: ghcr.io/piotrwojewoda/demo-symfony-k3s
  tag: "<short-sha>"        # <- the ONLY field Jenkins changes
ingress:
  host: demo.kreciowo.pl
  tlsSecret: kreciowo-dummy-tls
database:
  urlSecretRef: demo-app    # DATABASE_URL lives in this Secret
  urlSecretKey: DATABASE_URL
resources:
  requests: { cpu: 50m,  memory: 128Mi }
  limits:   { cpu: 300m, memory: 256Mi }
```

Validation rules:
- `image.tag` MUST match `^[0-9a-f]{7,40}$` or the literal `latest` for the
  very first install before the first build.
- `ingress.host` MUST end with `kreciowo.pl`.
- Resource limits MUST keep the whole node under 6 GB requested memory.

## Relationships

```text
GitOps repo (infr-as-a-code)
 ├── defines ArgoCD Applications ──▶ ArgoCD ──▶ applies Helm releases
 │        (root-app → demo-postgres, demo-symfony)
 ├── charts/demo-symfony ◀── used by ── Application demo-symfony
 └── values/demo-symfony.yaml ◀── bumped by ── Jenkins pipeline
App repo (demo-symfony-k3s)
 └── Jenkinsfile ──▶ Jenkins (polling) ──▶ Kaniko ──▶ ghcr.io image
```
