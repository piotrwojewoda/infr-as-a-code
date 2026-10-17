# Contract: Ingress & TLS

**Feature**: 001-k3s-cicd-platform | **Date**: 2026-10-17

## Routing table

| Hostname | Port | Backend service | Namespace | TLS secret | Certificate |
|----------|------|-----------------|-----------|------------|-------------|
| `kreciowo.pl` | 443→80 | `demo-symfony` :80 | `demo` | `kreciowo-tls` | **REAL** (home.pl DV, covers kreciowo.pl + www; loaded by operator, expires 2027-04-26) |
| `www.kreciowo.pl` | 443→80 | `demo-symfony` :80 | `demo` | `kreciowo-tls` | **REAL** (same secret) |
| `demo.kreciowo.pl` | 443→80 | `demo-symfony` :80 | `demo` | `kreciowo-dummy-tls` | dummy self-signed |
| `jenkins.kreciowo.pl` | 443→8080 | `jenkins` | `jenkins` | `kreciowo-dummy-tls` | dummy self-signed |
| `argocd.kreciowo.pl` | 443→80 | `argocd-server` (insecure mode behind proxy) | `argocd` | `argocd-server-tls` (fixed name required by the ArgoCD Helm chart) | dummy self-signed |

- Traefik terminates TLS; backends speak plain HTTP inside the cluster.
- Port 80 stays open (needed for the ACME HTTP-01 challenge if Let's Encrypt
  is enabled later). A redirect 80→443 is configured globally on Traefik.
- The operator's real certificate (2026-10-17) does NOT cover subdomains
  (SAN = kreciowo.pl, www.kreciowo.pl). That is why the app is served on the
  root domain and `demo.*` keeps the dummy cert. When a wildcard/SAN cert or
  Let's Encrypt arrives, re-point `clusters/malina/values/demo-symfony.yaml`
  and re-issue `argocd-server-tls` + `kreciowo-dummy-tls` in `jenkins`.

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
