# Feature 005: Deploy confirmation in the CI pipeline

**Status**: implemented | **Date**: 2026-10-25

## Problem

`Finished: SUCCESS` in Jenkins means only: tests passed, image pushed to
GHCR, GitOps tag bumped. ArgoCD syncs asynchronously (poll up to ~3 min),
then the image pull and rolling update take more time. The user sees a
green build minutes BEFORE the new version is actually live and cannot
tell when the deployment really finished (observed on the 2026-10-25
rebuild: ~3–6 min gap).

## User Story 1 — Build is green only when the release is live (P1)

As the operator, when the pipeline finishes green, I want to know the new
pod is already running on the cluster, so that "green build" == "page is
live".

**Acceptance**:

1. Given a pushed commit, when the pipeline reaches its last stage, then
   it waits until the demo Deployment runs the image with the new tag AND
   `rollout status` reports success — only then the build is green.
2. Given ArgoCD has not synced yet, when the stage starts, then it nudges
   ArgoCD (`refresh=hard` annotation) so the wait is seconds, not minutes.
3. Given the rollout stalls (image pull error, crash loop), when the
   timeout passes, then the build FAILS loudly (red), so a broken release
   is never reported as success.

## Requirements

- **FR-001**: `ciPipeline.groovy` gains a final `Deploy` stage after
  `Update GitOps`. It runs in a `kubectl` container inside the same agent
  pod. Budget: fits the existing 30-minute pipeline timeout.
- **FR-002**: The stage refreshes the ArgoCD app, waits until
  `deployment.spec.template.spec.containers[0].image` ends with the built
  tag (max ~6 min), then blocks on `kubectl rollout status` (max 5 min).
  Any timeout fails the build.
- **FR-003**: The stage MUST NOT weaken the GitOps rule — it only observes
  the cluster (get/list/watch, annotate), never mutates the app Deployment.
- **FR-004**: Agent pods use a dedicated ServiceAccount `jenkins-agent`
  with least-privilege RBAC: `get/list/watch` Deployments in the app
  namespace; `get/patch/update` Applications (argoproj.io) in `argocd`.
- **FR-005**: kubectl image MUST support linux/arm64 (Constitution).
- **FR-006**: Target app/namespace/deployment are parameters of the shared
  library (no hardcoding); the app Jenkinsfile declares them.

## Out of scope

- ArgoCD incoming webhook (instant sync via a public `/argocd/api/webhook`
  route) — possible later; needs a spec 003 contract change.
- Slack/mail notifications.

## Success criteria

- **SC-001**: A release build ends green only after the new pod is Ready;
  the console log shows the watched image tag and the rollout result.
- **SC-002**: Time from "Update GitOps" push to live pod is < 2 min in the
  normal case (refresh annotation instead of the 3-min poll).
- **SC-003**: A broken image (e.g. unpullable tag) turns the build red at
  the Deploy stage.
