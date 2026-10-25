# Tasks: Rancher and on-demand cluster load testing

- [x] T001 Add pinned Rancher ArgoCD application and Pi/LAN/TLS values.
- [x] T002 Add kube-burner Helm chart, opt-in Job and bounded CPU workload.
- [x] T003 Add least-privilege RBAC and secure pod contexts.
- [x] T004 Add kube-burner ArgoCD application and safe malina defaults.
- [x] T005 Document Rancher login, load-test operation and rebuild.
- [x] T006 Helm rendering, offline YAML assertions and arm64 image checks.
  (`kubectl apply --dry-run` needs a reachable cluster and remains part of T007.)
- [ ] T007 After merge: sync ArgoCD, run the five-pod smoke test, verify
  Grafana/logs/cleanup, and confirm Rancher is reachable only from LAN.
