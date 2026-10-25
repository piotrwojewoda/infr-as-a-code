# Plan: Rancher and on-demand cluster load testing

## Architecture

1. Add a multi-source ArgoCD application for the pinned upstream Rancher chart;
   keep cluster-specific values in `clusters/malina/values/rancher.yaml`.
2. Reuse cert-manager and Traefik. Use Rancher's self-signed certificate because
   the purchased non-wildcard certificate does not cover the Rancher hostname.
   Reuse the existing `lan-only` middleware.
3. Add a small local Helm chart for kube-burner. Its ServiceAccount, ConfigMap
   and RBAC are always present, but its benchmark Job is opt-in.
4. Configure a fixed, disposable test namespace. Pods run a bounded BusyBox CPU
   loop; `global.gc` removes benchmark resources after `jobPause`.
5. Run a test by changing values and committing. Use a new `runID` per run and
   disable the Job after collecting logs. Do not use ad-hoc cluster mutations.

## Resource and security choices

- Rancher: one replica, 250m/512Mi requested and 1 CPU/2Gi limited.
- Default test: five pods, each limited to 100m CPU and 32Mi memory.
- kube-burner: 500m CPU and 256Mi memory limit; ten-minute Job deadline.
- No Secret read permissions, no persistent test resources, no public ingress.
- Set `KINE_COMPACT_TIMEOUT=5m` on the k3s service. The default five-second
  SQLite compaction timeout can otherwise stop the whole control plane when
  Rancher's first-boot writes stall on SD storage.

## Verification

Render both Helm charts, validate every ArgoCD application with client dry-run,
check enabled and disabled Job rendering, verify YAML and shell syntax, and
confirm that both main images and the BusyBox workload image publish arm64
manifests. Live rollout remains an operator step after merge to `main`.
