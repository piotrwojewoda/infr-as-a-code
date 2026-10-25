# Tasks: Pod load monitoring (spec 006)

- [x] T001 `charts/monitoring/Chart.yaml`: umbrella chart, dependencies
  prometheus-community/prometheus 29.38.0 + grafana/grafana 10.5.15
- [x] T002 `charts/monitoring/values.yaml` + `clusters/malina/values/monitoring.yaml`:
  server-only Prometheus (no alertmanager/pushgateway/node-exporter),
  retention 24h, PVC 2 Gi, 30s scrape, Pi-sized resources; Grafana with
  provisioned datasource + dashboard sidecar, ingress
  `kreciowo.pl/grafana` LAN-only + `kreciowo-tls`
- [x] T003 `charts/monitoring/dashboards/pod-resources.json` +
  ConfigMap template (dashboard as code)
- [x] T004 `clusters/malina/apps/monitoring.yaml`: ArgoCD app, sync-wave 1
- [x] T005 `10-install-platform.sh`: ns `monitoring` + Secret
  `grafana-admin` from `GRAFANA_ADMIN_PASSWORD` (generated when unset)
- [x] T006 `real-cert.sh`: kreciowo.pl targets gain `monitoring/kreciowo-tls`
- [x] T007 Docs: FROM-SCRATCH.md §6/§8/§9 (Grafana row, secrets, versions)
- [x] T008 Live: secrets created, ArgoCD sync, Prometheus targets up,
  dashboard shows per-pod series; FROM-SCRATCH verified rows updated
  (2026-10-25: all targets `up`, 23 pod series, dashboard uid
  `pod-resources` provisioned, app `Synced/Healthy`)

## Verification (T008)

`kubectl -n monitoring get pods`; Prometheus `/targets` kubelet job up;
Grafana dashboard renders without UI setup; LAN-only enforced.
