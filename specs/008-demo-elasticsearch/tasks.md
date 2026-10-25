# Tasks: demo app uses Elasticsearch (spec 008)

- [ ] T001 App: `composer require symfony/http-client`
- [ ] T002 App: `src/Service/ElasticsearchClient.php` (+
  `ElasticsearchUnavailable`) — HTTPS + basic auth + CA file, lazy seed
  of the `documents` index, search with `multi_match`
- [ ] T003 App: `SearchController` (`GET /search`, `GET /api/elastic`) +
  `templates/search.html.twig` + `.env` defaults
- [ ] T004 App tests: service unit test (MockHttpClient, seed + hits +
  failures), controller tests (unconfigured → 200 with notice / 503 JSON)
- [ ] T005 Chart `charts/demo-symfony`: `elasticsearch.*` values, env
  vars, both Secrets mounted `optional: true`
- [ ] T006 Docs: FROM-SCRATCH.md (env, secrets, verification) + AGENTS notes
- [ ] T007 Live: Jenkins build (image) → ArgoCD sync → `/search?q=malina`
  returns hits, `/api/elastic` shows ES 9.5.5, pod has both mounts

## Verification (T007)

```bash
curl -s https://kreciowo.pl/api/elastic | jq '.version.number'
curl -s "https://kreciowo.pl/search?q=malina" | grep -o 'result-card' | wc -l
kubectl -n demo exec deploy/demo-symfony -- ls /etc/es-credentials /etc/es-ca
```
