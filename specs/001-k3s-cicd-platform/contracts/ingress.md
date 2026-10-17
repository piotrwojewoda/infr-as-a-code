# Contract: Ingress & TLS

**Feature**: 001-k3s-cicd-platform | **Date**: 2026-10-17

## Routing table

The real certificate (home.pl DV) covers ONLY `kreciowo.pl` +
`www.kreciowo.pl` (no wildcard). Therefore EVERYTHING is served under the main
domain with path-based routing; subdomains keep the dummy cert.

| URL | Backend service | Namespace | TLS secret | Certificate |
|-----|-----------------|-----------|------------|-------------|
| `https://kreciowo.pl/` | `demo-symfony` :80 | `demo` | `kreciowo-tls` | **REAL** (home.pl DV, expires 2027-04-26; loaded by operator — key never in git) |
| `https://www.kreciowo.pl/` | `demo-symfony` :80 | `demo` | `kreciowo-tls` | **REAL** (same secret) |
| `https://kreciowo.pl/jenkins/` | `jenkins` :8080 (controller runs with `--prefix=/jenkins`) | `jenkins` | `kreciowo-tls` | **REAL** (same cert, own secret copy in this namespace) |
| `https://kreciowo.pl/argocd/` | `argocd-server` :80 (`server.basehref` + `server.rootpath` = `/argocd`) | `argocd` | `argocd-server-tls` (fixed name required by the ArgoCD chart — now holds the REAL cert) | **REAL** |
| `https://demo.kreciowo.pl/` | `demo-symfony` :80 (alias) | `demo` | `kreciowo-dummy-tls` | dummy self-signed |

- Traefik terminates TLS; backends speak plain HTTP inside the cluster.
- Port 80 stays open (needed for the ACME HTTP-01 challenge if Let's Encrypt
  is enabled later). A redirect 80→443 is configured globally on Traefik.
- If a wildcard/SAN certificate (or Let's Encrypt) becomes available, move
  Jenkins/ArgoCD back to subdomains: change `hostName`/`path` in
  `clusters/malina/bootstrap/jenkins-values.yaml` and `argocd-values.yaml`,
  drop `jenkinsUriPrefix` + `server.basehref`/`rootpath`, re-issue secrets.

## Note: the same Secret CONTENT exists in three namespaces

Kubernetes TLS secrets are namespaced, so the real cert was loaded three
times: `kreciowo-tls` (demo), `kreciowo-tls` (jenkins), `argocd-server-tls`
(argocd). All three are created by the OPERATOR by hand
(quickstart.md "Swap the dummy certificate", Option B) — never by git.

## Certificate lifecycle

1. **Now (dummy)**: cert-manager `ClusterIssuer/selfsigned-dummy` issues one
   certificate per namespace, DNS names `kreciowo.pl` + `*.kreciowo.pl`,
   secret name `kreciowo-dummy-tls` in each namespace.
2. **Later (real)**: operator applies `ClusterIssuer` for the real CA (the
   `letsencrypt-prod` manifest is already prepared in
   `clusters/malina/infrastructure/cluster-issuers.yaml`) and re-issues. No
   application or ingress change is needed — the secret name stays the same.

## Invariants

- Every platform hostname MUST be served over HTTPS (FR-003).
- TLS secret names are stable; only the issuer changes.
- No certificate private key is ever committed to git.
