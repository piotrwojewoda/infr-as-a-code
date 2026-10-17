# Phase 0 Research: Hardening Decisions

**Feature**: 003-security-hardening | **Date**: 2026-10-17

Every decision below was checked against the constitution. Because the
cluster is being rebuilt (SD-card corruption from the 2026-10-17 power cut),
decisions are design-level; each one has a validation step in quickstart.md
to be executed on the rebuilt cluster.

## D1 — UI restriction: Traefik `ipAllowList` middleware, split by path

- **Decision**: Create one Traefik Middleware CRD `lan-only`
  (`traefik.io/v1alpha1`, `ipAllowList` with the RFC1918 ranges
  `192.168.0.0/16`, `10.0.0.0/8`, `172.16.0.0/12`) in
  `clusters/malina/infrastructure/traefik-security.yaml`. Attach it to the
  existing Jenkins and ArgoCD ingresses via the annotation
  `traefik.ingress.kubernetes.io/router.middlewares:
  <ns>-lan-only@kubernetescrd` in their Helm values. Add a **separate**
  Ingress for the webhook path `kreciowo.pl/jenkins/github-webhook/` with NO
  middleware, so GitHub keeps reaching it. Traefik routes by longest path
  prefix, so `/jenkins/github-webhook/` wins over `/jenkins` and stays
  public; everything else under `/jenkins` and `/argocd` is LAN-only.
- **Alternatives**:
  - *One ingress + middleware chain with path exemption* — Traefik
    middlewares apply per-route; exemptions require separate routes anyway.
  - *Fail2ban on Traefik logs / rate-limit middleware on login forms* —
    weakens the guarantee from "unreachable" to "slowed down"; rejected by
    the stakeholder (UI must be LAN-only).
  - *Disable ingresses, SSH-tunnel for admin access* — most secure, but too
    much friction for a homelab (KISS).
- **Why**: configuration of an existing component (no new pods), path-level
  precision, verifiable with one curl from outside and one from inside.

## D2 — Client-IP correctness behind router NAT and k3s ServiceLB

- **Decision**: The router port-forward preserves the client source IP (pure
  DNAT). k3s ServiceLB (Klipper) exposes Traefik as hostPorts on the node;
  inbound packets keep their source address, so Traefik sees the real client
  IP and `ipAllowList` evaluates correctly. The default `ipStrategy`
  (remote address, no X-Forwarded-For depth) is correct — there is no CDN or
  second proxy in front.
- **Risk to validate**: if any hop masquerades sources, restricted paths
  would see the node IP (which is RFC1918) and let everyone in. Validation
  step in quickstart.md: probe from a non-LAN network MUST return 403; if it
  returns 200, set `externalTrafficPolicy: Local` on the Traefik service.
  This is the single highest-risk assumption of the feature — hence tested
  first (SC-001).
- **Alternatives**: PROXY protocol (no second proxy — pointless); trusting
  X-Forwarded-For (spoofable — explicitly not used).

## D3 — SSH: key-only via bootstrap-provisioned public key

- **Decision**: New `clusters/malina/bootstrap/05-hardening.sh` (runs after
  `00-install-k3s.sh`, before `10-install-platform.sh`):
  1. installs `clusters/malina/bootstrap/ssh-keys/malina-master.pub` into
     `/home/malina-master/.ssh/authorized_keys` (idempotent),
  2. **verifies** a key-based login works before touching sshd (the script
     aborts if it cannot prove access — lockout protection),
  3. writes `/etc/ssh/sshd_config.d/99-malina.conf`:
     `PasswordAuthentication no`, `KbdInteractiveAuthentication no`,
     `PermitRootLogin no`,
  4. restarts `sshd` (Debian 12 uses socket activation — the script restarts
     `ssh.socket`/`ssh.service` as applicable).
- **Public key in git is not a secret** — it is public by design (same class
  of information as a username). Constitution III unaffected. Key rotation =
  replace the file, commit, re-run the script.
- **Alternatives**: password auth + fail2ban only (weak password stays a
  risk — rejected); changing the SSH port (obscurity only, breaks muscle
  memory, no real gain once passwords are off).

## D4 — Host firewall: ufw with explicit k3s allowances

- **Decision**: `ufw` (Debian standard, tiny) configured by `05-hardening.sh`:
  - `default deny incoming`, `default allow outgoing`,
  - allow `22/tcp`, `80/tcp`, `443/tcp` from anywhere,
  - allow the cluster registry `30500/tcp` from `192.168.0.0/16` (LAN builds;
    never router-forwarded),
  - allow cluster-internal traffic on the pod/service networks
    (`10.42.0.0/16` pods, `10.43.0.0/16` services) and on the loopback and
    `cni0`/`flannel*` interfaces,
  - allow flannel VXLAN `8472/udp` and kubelet `10250/tcp` from the node
    itself (single node today; keeps a second node possible),
  - `default allow routed` is NOT set globally; instead forwarding is
    allowed between the pod CIDRs and the node so ServiceLB DNAT works.
  The exact rule list is the contract in contracts/host-hardening.md.
- **Alternatives**: hand-written nftables (more control, much more to
  maintain — KISS); no firewall (router already filters — but then a router
  misconfiguration silently exposes everything; the spec wants the guarantee
  local to the Pi).
- **Risk to validate**: k3s networking is iptables-heavy; the quickstart
  runs a full pipeline (build → tests → deploy) with ufw active to prove
  nothing internal is blocked (SC-004, FR-007).

## D5 — Brute-force protection: fail2ban for sshd only

- **Decision**: Install `fail2ban` with a single sshd jail (Debian default
  backend `systemd`): `maxretry 5`, `findtime 10m`, `bantime 1h`. No Traefik
  jails — after D1 there is no public login form left to brute-force (the
  webhook is HMAC-protected, not password-based).
- **Alternatives**: CrowdSec (heavier agent + central account — overkill,
  Constitution IV); sshd `MaxAuthTries` alone (no temporary bans).

## D6 — Automatic security updates, no automatic reboot

- **Decision**: Install `unattended-upgrades`, enable the Debian security
  origin only, keep automatic reboot OFF. A single-node cluster must not
  reboot itself; the runbook documents a monthly manual reboot check
  (`/var/run/reboot-required`).
- **Alternatives**: full upgrades including non-security (riskier on a Pi
  running stateful workloads); auto-reboot at night (cluster downtime with
  no operator present — rejected).
- **Why**: security patches land within 24 h without risking unplanned
  cluster outages. Documented trade-off in the runbook.

## Verified facts used above

| Fact | Source | Result |
|------|--------|--------|
| Only ports 80/443 are forwarded to the Pi | operator confirmation | 2026-10-17 |
| SSH is not forwarded (LAN-only) | operator confirmation | 2026-10-17 |
| Public IP of the home network | `curl ifconfig.me` on the Pi | 185.236.108.103 |
| sshd listens on all interfaces, password auth at Debian default (on) | `ss` + `sshd_config` on the Pi | 2026-10-17 |
| No ufw / fail2ban installed on the host | `which` on the Pi | 2026-10-17 |
| GitHub webhooks reach Jenkins through `https://kreciowo.pl/jenkins/github-webhook/` | builds #10/#11 "Started by GitHub push" | 2026-10-17 |
| Operator's SSH public key | `~/.ssh/id_malina.pub` on the MacBook | ed25519, created 2026-10-17 |
| FS corruption cause = power cut by the operator | operator confirmation | re-flash fixes it; this feature must be part of the rebuild |
