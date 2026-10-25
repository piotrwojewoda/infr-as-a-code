# Tasks: Elasticsearch via ECK (spec 007)

- [x] T001 `charts/elasticsearch/`: Chart.yaml + values.yaml (ES 9.5.5,
  heap 512m, 200m/1.2Gi–1/1.5Gi, PVC 4Gi local-path, mmap off) +
  `templates/elasticsearch.yaml` (single-node CR `demo`)
- [x] T002 `clusters/malina/apps/elastic-operator.yaml`: helm chart
  elastic/eck-operator 3.5.0, ns `elastic-system`, sync-wave 0, trimmed
  operator resources
- [x] T003 `clusters/malina/apps/elasticsearch.yaml`: chart from this
  repo, ns `demo`, sync-wave 1
- [x] T004 Docs: FROM-SCRATCH.md versions/secrets/verification rows
- [ ] T005 Live: operator Healthy → ES `Ready/green`; authenticated query
  from a demo pod returns version 9.5.5

## Verification (T005)

`kubectl -n demo get elasticsearch demo`; run a curl pod with the
`elastic` password from `demo-es-elastic-user` against
`https://demo-es-http:9200` (CA from `demo-es-http-certs-public`).
