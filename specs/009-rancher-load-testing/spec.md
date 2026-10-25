# Feature 009: Rancher and on-demand cluster load testing

**Status**: implemented in GitOps, live deployment pending | **Date**: 2026-10-25

## Problem

The platform has no central cluster-management UI and no repeatable way to
generate Kubernetes load. The operator needs both without exposing an admin UI
publicly or leaving a stress workload running on the single Raspberry Pi.

## User stories

### US1 — Rancher (P1)

As the operator I open Rancher from the LAN and inspect the local k3s cluster.
Rancher is rebuilt by the normal bootstrap plus ArgoCD sync, without secrets in
git.

**Acceptance**: the `rancher` ArgoCD application is Healthy, the local cluster
is registered, and `https://rancher.kreciowo.pl` is LAN-only.

### US2 — Safe load test (P1)

As the operator I enable a versioned load-test run through git. kube-burner
creates a configurable number of CPU-consuming pods, waits, and removes its
test namespace. I observe the run in Grafana and inspect the benchmark logs.

**Acceptance**: the default sync creates no test Job; an enabled run completes,
cleans up `kube-burner-load`, and cannot read Kubernetes Secrets.

## Requirements

- **FR-001**: Rancher chart 2.15.2 is deployed by ArgoCD in `cattle-system`,
  with one replica and Pi-sized resource requests/limits.
- **FR-002**: Rancher uses the existing Traefik and cert-manager, is LAN-only,
  and has a generated bootstrap password (never a password in values/git).
- **FR-003**: kube-burner 2.8.6 is packaged as a Helm chart and managed by an
  ArgoCD application in `load-testing`.
- **FR-004**: the load Job is disabled by default. Each run has a unique
  `runID`; `iterations`, `replicas`, QPS and duration are values-controlled.
- **FR-005**: the test uses only its own `kube-burner-load` namespace, cleans it
  up automatically, and uses least-privilege RBAC.
- **FR-006**: every image supports `linux/arm64`; test and generated pods have
  resource limits and the benchmark has a deadline.
- **FR-007**: rebuild and daily-use instructions live in `FROM-SCRATCH.md` and
  this spec's quickstart.

## Success criteria

- Rancher and kube-burner ArgoCD applications are `Synced/Healthy`.
- No load Job exists with the default values.
- A five-pod smoke run finishes successfully, disappears after values are set
  back to `enabled: false`, and leaves no `kube-burner-load` namespace.
