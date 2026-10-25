# Tasks: demo app uses Elasticsearch (spec 008)

- [x] T001 App: `composer require symfony/http-client`
- [x] T002 App: `src/Service/ElasticsearchClient.php` (+
  `ElasticsearchUnavailable`) — HTTPS + basic auth + CA file, lazy seed
  of the `documents` index, search with `multi_match`
- [x] T003 App: `SearchController` (`GET /search`, `GET /api/elastic`) +
  `templates/search.html.twig` + `.env` defaults
- [x] T004 App tests: service unit test (MockHttpClient, seed + hits +
  failures), controller tests (unconfigured → 200 with notice / 503 JSON)
- [x] T005 Chart `charts/demo-symfony`: `elasticsearch.*` values, env
  vars, both Secrets mounted `optional: true`
- [x] T006 Docs: FROM-SCRATCH.md (env, secrets, verification) + AGENTS notes
- [x] T007 Live: Jenkins build (image) → ArgoCD sync → `/search?q=malina`
  returns hits, `/api/elastic` shows ES 9.5.5, pod has both mounts

## Verification (T007)

```bash
curl -s https://kreciowo.pl/api/elastic | jq '.version.number'
curl -s "https://kreciowo.pl/search?q=malina" | grep -o 'result-card' | wc -l
kubectl -n demo exec deploy/demo-symfony -- ls /etc/es-credentials /etc/es-ca
```

## Verification result (2026-10-25, build #4)

- Jenkins build **#4 SUCCESS** (image `ec51c4e`), ArgoCD `Synced/Healthy`,
  pod `demo-symfony-5c98dcf7d8-4lfhg` Running.
- `GET /api/elastic` -> `{"status":"ok","cluster":"demo","version":"9.5.5"}`.
- `GET /search?q=malina` -> result card; `?q=raspberry` -> 1 result.
- ES index `documents` count = **4** (lazy seed worked).
- Both secrets mounted: `/etc/es-credentials/elastic`, `/etc/es-ca/ca.crt`.
- App footprint: 51 MiB RAM, 1m CPU (Grafana `demo` namespace unchanged
  in size); start page untouched (`/`, `/healthz` still OK).
