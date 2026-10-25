# Feature 008: Demo app uses Elasticsearch

**Status**: implemented | **Date**: 2026-10-25

## Problem

Elasticsearch (spec 007) runs in namespace `demo`, but nothing uses it.
The demo application needs to show that the cluster is a real platform:
index a few documents and search them.

## User Story 1 — Search page backed by Elasticsearch (P1)

As a visitor I open `https://kreciowo.pl/search`, type a word and get
results from Elasticsearch, so that the demo proves the full chain
(app → in-cluster TLS service → ES).

**Acceptance**:

1. Given the demo app is deployed and ES is `Ready`, when I open
   `/search?q=malina`, then I see result cards with title + snippet and
   the total hit count.
2. Given the index does not exist yet, when the first search runs, then
   the app creates the index and seeds the demo documents (idempotent,
   stable document IDs).
3. Given ES is unreachable or not yet configured, when I open `/search`
   or `/api/elastic`, then I get a friendly "search unavailable" page /
   HTTP 503 JSON — never a stack trace, and the start page keeps working.

## Requirements

- **FR-001**: The app talks to ES over HTTPS with basic auth using
  `symfony/http-client` (no Elasticsearch PHP client — smaller image,
  fewer dependencies, KISS).
- **FR-002**: Connection settings come only from environment:
  `ELASTICSEARCH_URL`, `ELASTICSEARCH_USER`,
  `ELASTICSEARCH_PASSWORD_FILE`, `ELASTICSEARCH_CA`. The password and
  the CA are **mounted from ECK-generated Secrets** (`demo-es-elastic-user`,
  `demo-es-http-certs-public`) and read at request time — never in git,
  never in the image (Constitution III).
- **FR-003**: Both Secrets are mounted `optional: true`, so the pod can
  start before ES is ready; the feature recovers without a restart once
  ECK creates them.
- **FR-004**: `GET /search` (HTML, same look as the start page),
  `GET /api/elastic` (JSON health/info). The start page
  (`/`, `/healthz`) is untouched — probes must not depend on ES.
- **FR-005**: The demo documents are seeded lazily (index `documents`,
  stable IDs, `refresh=true`) — after a rebuild the first search
  recreates them; nothing to run by hand.
- **FR-006**: Wiring lives in `charts/demo-symfony` (values-driven) so
  another cluster can disable it with `elasticsearch.enabled: false`.
- **FR-007**: Tests must pass **without** ES (CI has no ES): the service
  is unit-tested with `MockHttpClient`, the controller tests cover the
  graceful-degradation paths.

## Notes — SD card / Pi

Searches are read-mostly; the only writes are the four seed documents on
the first request. Index size is a few KB.

## Success criteria

- **SC-001**: `https://kreciowo.pl/search?q=malina` returns 200 with
  hits; `https://kreciowo.pl/api/elastic` shows cluster `demo`,
  version 9.5.5.
- **SC-002**: `kubectl -n demo describe pod` shows the two Secrets
  mounted; no credential in git or in the image.
- **SC-003**: Jenkins build + ArgoCD sync deploys it; Grafana shows the
  `demo` namespace unchanged in size (< 50 MB RAM extra for the app).
