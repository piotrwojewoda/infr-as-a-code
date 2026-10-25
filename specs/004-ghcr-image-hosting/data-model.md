# Data Model: Move Image Hosting to GitHub Container Registry

**Feature**: 004-ghcr-image-hosting | **Date**: 2026-10-25

## Registry entities

| Entity | Where | Attributes | Owner |
|--------|-------|------------|-------|
| GHCR package | `ghcr.io/piotrwojewoda/<app>` | private, ARM64, tags `<short-sha>` + `latest` | Jenkins (push), kubelet (pull) |
| `image.repository` | `clusters/malina/values/demo-symfony.yaml` | `ghcr.io/piotrwojewoda/demo-symfony-k3s` | GitOps |
| `image.tag` | same file | short Git SHA; bumped by the pipeline only | Jenkins |
| `imagePullSecrets` | same file | `[{ name: ghcr-pull }]` | GitOps |

## Secret entities (created at bootstrap, never in git)

| Secret | Namespace | Type | Key | Used by |
|--------|-----------|------|-----|---------|
| `ghcr-push` | `jenkins` | `kubernetes.io/dockerconfigjson` | `.dockerconfigjson` → mounted as `/kaniko/.docker/config.json` | Kaniko push |
| `ghcr-pull` | `demo` | `kubernetes.io/dockerconfigjson` | `.dockerconfigjson` | kubelet pull |
| `jenkins-github` | `jenkins` | Opaque | `username`, `token`, `webhook-secret` | JCasC + GitOps tag bump |

Both GHCR Secrets are derived from the same operator PAT (`GITHUB_TOKEN`)
with `read:packages`, `write:packages` and `repo`.

## Pipeline data flow

```text
merge to app main
  -> Jenkins webhook
  -> Test stage (unchanged)
  -> Kaniko (ghcr-push mounted) -> ghcr.io/piotrwojewoda/<app>:<sha> + :latest
  -> git commit in infr-as-a-code: image.tag = <sha>
  -> ArgoCD sync (ghcr-pull) -> demo Pod pulls from GHCR
```

## Removed entities

| Entity | Kind | Reason |
|--------|------|--------|
| `registry` namespace | Namespace | no local registry |
| `registry` | Deployment | no local registry |
| `registry-data` | PVC (5 GiB) | no local image storage; reclaim SD space |
| `registry` | Service (NodePort 30500) | no local registry endpoint |
| `/etc/rancher/k3s/registries.yaml` mirror for `:30500` | host file | containerd no longer needs insecure access |
| ufw rule `30500/tcp` | host firewall | port no longer used |

## Validation states

| State | Expected |
|-------|----------|
| Pipeline with valid token | push succeeds, GitOps tag bumps, demo rolls out |
| Pipeline with missing `write:packages` | Kaniko `DENIED`, pipeline fails, deployment unchanged |
| Pod with valid `ghcr-pull` | `Running`/`Ready` |
| Pod with missing/expired `ghcr-pull` | `ImagePullBackOff`, old ReplicaSet still serving |
| Fresh bootstrap | no `registry` namespace, no 30500 rule, no mirror file |
