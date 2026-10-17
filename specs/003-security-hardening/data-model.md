# Phase 1 Data Model: Exposure and Host-Access Entities

**Feature**: 003-security-hardening | **Date**: 2026-10-17

No persistent database is added. These are the configuration entities and
the validation rules applied to them.

## ExposureRule

Binds an HTTP surface to a visibility class. Evaluated at the reverse proxy
before any application code runs.

| Field | Rule |
|-------|------|
| `path` | longest-prefix match wins over shorter prefixes |
| `visibility` | `public` or `lan-only` |
| `allowedSources` | for `lan-only`: RFC1918 ranges `192.168.0.0/16`, `10.0.0.0/8`, `172.16.0.0/12` |
| `rejectStatus` | HTTP 403 for disallowed sources |
| `evaluationPoint` | reverse proxy, before forwarding to the application |

### Instances

| Path | Visibility | Reason |
|------|-----------|--------|
| `/` on `demo.kreciowo.pl` (the whole demo site) | public | the point of the platform |
| `/jenkins/github-webhook/` | public | GitHub deliveries; protected by HMAC signature, not by passwords |
| `/.well-known/acme-challenge/` | public | future real certificate (HTTP-01) |
| `/jenkins` (all other paths) | lan-only | admin UI |
| `/argocd` (all paths) | lan-only | admin UI |

## HostAccessRule

| Field | Rule |
|-------|------|
| `sshAuth` | public-key only; password and keyboard-interactive disabled; root login disabled |
| `provisionedKeys` | exactly the public keys committed under `clusters/malina/bootstrap/ssh-keys/` |
| `bruteForce` | 5 failed SSH attempts within 10 min ⇒ source banned for 1 h |
| `firewallDefault` | inbound deny, outbound allow |
| `firewallAllowPublic` | TCP 22, 80, 443 from any source |
| `firewallAllowLan` | TCP 30500 (in-cluster registry) from `192.168.0.0/16` only |
| `firewallAllowCluster` | pod CIDR `10.42.0.0/16`, service CIDR `10.43.0.0/16`, loopback, `cni0`/`flannel*` interfaces, VXLAN `8472/udp`, kubelet `10250/tcp` node-local |
| `updates` | Debian security updates installed automatically; no automatic reboot |

## State transitions (a freshly re-flashed Pi)

```text
fresh OS ──00-install-k3s.sh──► k3s ready ──05-hardening.sh──► host hardened
                                                              (keys, sshd,
                                                              ufw, fail2ban,
                                                              updates)
     ──10-install-platform.sh──► platform running ──ArgoCD sync──► apps +
                                lan-only middleware active ◄───────────────┘
```

Invariant: at no point in the sequence is password SSH login enabled while a
key-based login is unverified (lockout guard in the script).
