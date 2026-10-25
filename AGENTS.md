# AGENTS.md — rules for coding agents in this repository

This repository is the GitOps source of truth for the "malina" k3s cluster
(Raspberry Pi CI/CD platform). Read `.specify/memory/constitution.md` first —
it is binding.

## Non-negotiables

- **Never commit secrets** (tokens, passwords, private keys). Kubernetes
  Secrets are created by `clusters/malina/bootstrap/10-install-platform.sh`
  from operator input. Git may contain secret *names* only.
- **Every cluster change goes through this repository.** Do not instruct the
  operator to run ad-hoc `kubectl`/`helm` mutations outside the bootstrap
  scripts; encode the change here instead.
- **Releases are image tags.** To change the deployed app version, change only
  `image.tag` in `clusters/malina/values/demo-symfony.yaml` (normally done by
  Jenkins). Never use `:latest` for a real release.
- **All images must support linux/arm64.**

## Conventions

- ArgoCD Applications live in `clusters/malina/apps/`; the `root-app` watches
  that directory (app-of-apps). Adding a file there = adding a managed app.
- Database before application: use the `argocd.argoproj.io/sync-wave`
  annotation (`1` = infra/DB, `2` = apps).
- Helm charts for applications live in `charts/<app>/`. Environment-specific
  values live in `clusters/<cluster>/values/<app>.yaml` and are wired through
  ArgoCD multi-source applications (`$values` ref).
- Spec Kit workflow is used for changes: `/speckit.specify` → `/speckit.plan`
  → `/speckit.tasks` → `/speckit.implement`. Specs live in `specs/`.
- `clusters/malina/bootstrap/FROM-SCRATCH.md` is the living rebuild runbook.
  Every change to the platform (bootstrap scripts, pinned versions, secrets
  flow, network, TLS) MUST update it in the same commit.
- Documentation language: simplified English.

## Verification before committing

```bash
helm template charts/demo-symfony \
  --values clusters/malina/values/demo-symfony.yaml | kubectl apply --dry-run=client -f -
kubectl apply --dry-run=client -f clusters/malina/apps/
```
