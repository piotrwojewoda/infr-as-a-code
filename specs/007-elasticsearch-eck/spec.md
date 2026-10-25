# Feature 007: Elasticsearch (ECK) for the demo project

**Status**: implemented | **Date**: 2026-10-25

## Problem

The demo project needs a search engine. There is no Elasticsearch on the
cluster. It must run on the same single Raspberry Pi (8 GB) next to the
existing platform — so it has to be tightly sized (Constitution IV).

## User Story 1 — Single-node Elasticsearch in the demo namespace (P1)

As the operator I want an ECK-managed, single-node Elasticsearch cluster
running in namespace `demo`, reachable from the demo pods, so that the
demo application can index and search documents.

**Acceptance**:

1. Given the ArgoCD apps are synced, when I check
   `kubectl -n demo get elasticsearch`, then the cluster `demo` is
   `Ready/green` with one node.
2. Given a pod in `demo`, when I query
   `https://demo-es-http:9200` with the `elastic` user, then I get the
   Elasticsearch info JSON (TLS via the ECK CA, secret
   `demo-es-http-certs-public`).
3. Given a Jenkins build + Grafana open, when Elasticsearch idles, then
   the Pi still has head-room (ES heap fixed at 512 MB, cgroup limits set).

## Requirements

- **FR-001**: ECK operator (helm chart `elastic/eck-operator` **3.5.0**)
  in namespace `elastic-system`, trimmed resources, managed by ArgoCD app
  `elastic-operator` (sync-wave **0**).
- **FR-002**: One `Elasticsearch` CR `demo` (version **9.5.5**) in
  namespace `demo` via our own chart `charts/elasticsearch`, ArgoCD app
  `elasticsearch` (sync-wave **1**). Single node.
- **FR-003**: Size for the Pi: heap 512 MB (Xms=Xmx), requests
  200m/1.2 Gi, limits 1/1.5 Gi, PVC 4 Gi `local-path`,
  `node.store.allow_mmap: false` (SD card, see note).
- **FR-004**: `vm.max_map_count` handled by ECK's default privileged
  os-settings init container — no host changes.
- **FR-005**: Credentials: the operator-generated Secret
  `demo-es-elastic-user` (never in git, Constitution III). App wiring
  (env vars in the demo chart) is a later step, not part of this feature.
- **FR-006**: No Kibana (KISS — can be added later the same way).
- **FR-007**: All images MUST support linux/arm64 (official Elastic
  images are multi-arch ✓).

## Notes — SD card wear

An idle demo Elasticsearch writes little (no ingest). `allow_mmap: false`
avoids memory-mapped index files on the SD card; the 4 Gi PVC caps the
footprint. JVM heap is fixed so GC pressure stays predictable.

## Success criteria

- **SC-001**: `kubectl -n elastic-system get pods` operator Running;
  `kubectl -n demo get elasticsearch demo` = `Ready`, health `green`.
- **SC-002**: Authenticated query from inside the cluster returns
  `"cluster_name" : "demo"` (or `docker-cluster` name) and version 9.5.5.
- **SC-003**: Everything rebuilds from git: bootstrap + one ArgoCD sync
  (Constitution I), docs in FROM-SCRATCH.md updated.
