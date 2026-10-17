# Contract: Exposure Matrix (what the internet may see)

**Feature**: 003-security-hardening | **Date**: 2026-10-17

This matrix is binding. If a future change adds a public endpoint, it MUST be
added here first (GitOps: the matrix is the review checklist for exposure).

## HTTP paths (ports 80/443, the only router-forwarded ports)

| Path | Visibility | Enforcement | Notes |
|------|-----------|-------------|-------|
| `demo.kreciowo.pl/` (whole demo site) | public | no middleware | must keep returning 200 |
| `kreciowo.pl/jenkins/github-webhook/` | public | no middleware | GitHub posts; HMAC `X-Hub-Signature-256` verified by Jenkins |
| `*/.well-known/acme-challenge/*` | public | no middleware | reserved for the real certificate swap |
| `kreciowo.pl/jenkins` + everything below (except the webhook path above) | LAN-only | Traefik middleware `lan-only` (ipAllowList RFC1918) → 403 otherwise | login UI not internet-visible |
| `kreciowo.pl/argocd` + everything below | LAN-only | same middleware | login UI not internet-visible |
| any other host/path | public by accident of routing | — | Traefik returns its default 404; no application is exposed |

## TCP ports (host firewall)

| Port | Source | Service |
|------|--------|---------|
| 22 | any (router does not forward it today) | sshd, public-key only |
| 80 | any | Traefik → redirect to 443 |
| 443 | any | Traefik (matrix above) |
| 30500 | `192.168.0.0/16` only | in-cluster image registry (NodePort) |
| 6443 | node-local | k3s apiserver |
| 8472/udp | node-local | flannel VXLAN |
| 10250 | node-local | kubelet |
| everything else inbound | denied | — |

## Guarantees this contract must keep

- A GitHub webhook POST from the internet reaches Jenkins (pipeline triggers).
- The demo page answers the public internet.
- A scanner hitting `/jenkins` or `/argocd` from the internet gets 403.
- Cluster-internal HTTP (pods → services, webhooks between Traefik and pods)
  is unaffected.
