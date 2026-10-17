# Contract: CI Pipeline (Jenkins)

**Feature**: 001-k3s-cicd-platform | **Date**: 2026-10-17

## Trigger

- Input event: a new commit on branch `main` of `piotrwojewoda/demo-symfony-k3s`.
- Detection: Jenkins SCM polling, cron `* * * * *` (until webhooks are possible).

## Stages (must run in this order)

1. **Checkout** — full clone of the app repo at the merged commit.
2. **Build & Push** — Kaniko builds `Dockerfile` from the repo root and pushes
   to the in-cluster registry (NodePort 30500, plain HTTP → `--insecure`):
   - `192.168.68.52:30500/demo-symfony-k3s:<short-sha>` (immutable release)
   - `192.168.68.52:30500/demo-symfony-k3s:latest` (convenience tag)
3. **Update GitOps repo** — clone `piotrwojewoda/infr-as-a-code`, set
   `image.tag: <short-sha>` in `clusters/malina/values/demo-symfony.yaml`,
   commit `chore(release): demo-symfony-k3s <short-sha>`, push to `main`.
4. **Deploy** — no direct action. ArgoCD notices the GitOps change and syncs.

## Inputs (from Kubernetes Secret `jenkins-github`, namespace `jenkins`)

| Variable | Purpose |
|----------|---------|
| `GITHUB_USER` | git push user |
| `GITHUB_TOKEN` | PAT with `repo` scope — used ONLY to push the GitOps tag bump. Image push needs no auth (in-cluster registry). |

## Guarantees

- A failed stage stops the pipeline; the running deployment is untouched.
- The GitOps commit is the only deployment trigger — no `kubectl` from Jenkins.
- Every pushed image tag is immutable (`<short-sha>`), so rollbacks are
  "change the tag back" commits.
- Pipeline definition lives in the app repo (`Jenkinsfile`) — code, not clicks.

## Failure handling

| Failure | Result |
|---------|--------|
| Build fails | No image pushed, no GitOps commit, old version keeps running |
| Push fails | Same as above |
| GitOps push fails | Image exists but is not deployed; next successful run recovers |
