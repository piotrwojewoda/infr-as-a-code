# Feature 006: Pod load monitoring — Prometheus + Grafana

**Status**: implemented | **Date**: 2026-10-25

## Problem

There is no visibility into pod resource usage (CPU/memory) on the
cluster. The operator cannot see how much load Jenkins builds, the demo
app or the platform itself put on the single 8 GB Raspberry Pi.

## User Story 1 — Grafana dashboard with per-pod CPU/memory (P1)

As the operator I open `https://kreciowo.pl/grafana` (from the LAN),
log in, and see a dashboard with per-pod CPU and memory usage, so that I
can spot overload before the Pi starts swapping.

**Acceptance**:

1. Given the monitoring app is synced, when I open the dashboard, then I
   see CPU and memory time series per pod for all namespaces.
2. Given a Jenkins build runs, when I watch the dashboard, then the
   `jenkins` namespace pods spike visibly.
3. Given the cluster is rebuilt from scratch (FROM-SCRATCH.md), when the
   bootstrap and one ArgoCD sync finish, then monitoring is back
   including the dashboard (dashboards as code, Constitution II).

## Requirements

- **FR-001**: Prometheus scrapes kubelet/cAdvisor metrics
  (`container_cpu_usage_seconds_total`, `container_memory_working_set_bytes`)
  via the chart's default `kubernetes-nodes-cadvisor` job (kubelet
  :10250 https + SA token); no node-exporter, no alertmanager (KISS,
  Constitution IV).
- **FR-002**: Small footprint: retention 24h, PVC ≤ 2 Gi (local-path),
  scrape interval 30s, resource limits sized for the Pi.
- **FR-003**: Grafana with the Prometheus datasource and the
  "Pod resources" dashboard provisioned **from git** (ConfigMap), not
  clicked in the UI.
- **FR-004**: Grafana UI on `kreciowo.pl/grafana`, **LAN-only** (the
  existing `lan-only` Traefik middleware, spec 003), TLS secret
  `kreciowo-tls` (real cert via `real-cert.sh`).
- **FR-005**: Admin password from operator env (`GRAFANA_ADMIN_PASSWORD`)
  → Secret `grafana-admin` created by `10-install-platform.sh`;
  never in git (Constitution III).
- **FR-006**: Deployed as ArgoCD app `monitoring` (app-of-apps,
  `clusters/malina/apps/monitoring.yaml`, sync-wave 1) using an umbrella
  chart `charts/monitoring` with pinned dependency versions.
- **FR-007**: All images MUST support linux/arm64 (Constitution).

## Notes — SD card wear

Prometheus writes its TSDB to the SD card. Mitigation: retention 24h,
30s scrape interval, single node — expected write volume is a few MB/h,
negligible next to the container image pulls the SD already survived.
No remote TSDB (KISS).

## Success criteria

- **SC-001**: `kubectl -n monitoring get pods` all Running; Prometheus
  targets show the kubelet/cAdvisor job up.
- **SC-002**: The provisioned dashboard renders live per-pod series
  without any UI setup.
- **SC-003**: Grafana is unreachable from outside the LAN (middleware),
  reachable inside with the real kreciowo.pl certificate.
