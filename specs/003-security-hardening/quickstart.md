# Quickstart: Validating the Hardening (and the Rebuilt Cluster)

**Feature**: 003-security-hardening | **Date**: 2026-10-17

Prerequisite: a freshly re-flashed Pi where the operator ran, in order:
`00-install-k3s.sh` → `05-hardening.sh` → `10-install-platform.sh` →
`kubectl apply -f ../apps/root-app.yaml` (see bootstrap README). Nothing
else should be needed — that is the point of this feature.

## Scenario A — rebuild acceptance (the whole feature in one run)

On a fresh card the three scripts run unattended and end with: k3s Ready,
host hardened, platform up, ArgoCD syncing, hardening active. If any step
needs manual fixing, this scenario fails.

## Scenario B — admin UIs are LAN-only (SC-001)

1. From a network outside the home LAN (phone on mobile data is simplest):
   - `curl -sk -o /dev/null -w '%{http_code}\n' https://kreciowo.pl/jenkins/` → **403**
   - `curl -sk -o /dev/null -w '%{http_code}\n' https://kreciowo.pl/argocd/` → **403**
2. From the LAN: both URLs return the login pages (200).
3. If the outside probe returns 200 instead of 403, the client IP is being
   masqueraded somewhere — apply research.md D2 fallback
   (`externalTrafficPolicy: Local` on the Traefik service) and re-test.

## Scenario C — public surfaces stay public (SC-002)

1. From outside the LAN: `https://demo.kreciowo.pl/` → 200.
2. Merge a small change to `main` of `demo-symfony-k3s` → the GitHub webhook
   reaches Jenkins and the pipeline deploys it (proves the webhook path is
   still public AND the test gate from spec 002 still works, FR-010).
3. Reserved for the cert swap: `/.well-known/acme-challenge/` must not be
   LAN-restricted (check the Ingress/middleware wiring).

## Scenario D — SSH is key-only (SC-003)

1. From the operator MacBook: `ssh -i ~/.ssh/id_malina malina-master@192.168.68.52`
   → logged in, no password prompt.
2. `ssh -o PubkeyAuthentication=no malina-master@192.168.68.52`
   → `Permission denied (publickey).` — no password prompt at all.
3. Brute-force check: 6 failed attempts in a row from a test client →
   `fail2ban-client status sshd` on the Pi shows the source as banned.

## Scenario E — firewall and updates (SC-004)

1. From the LAN: `nmap -p- -T4 192.168.68.52` → only `22`, `80`, `443` open
   (6443 may show as open to the LAN — it is the apiserver; acceptable and
   documented in contracts/exposure.md).
2. With ufw active, run one full pipeline (merge to main → deployed) and one
   ArgoCD sync → both succeed (FR-007).
3. On the Pi: `systemctl is-enabled unattended-upgrades` → `enabled`;
   `grep Automatic-Reboot /etc/apt/apt.conf.d/50unattended-upgrades` →
   `"false"`.

## Rollback

- Proxy layer: remove the middleware annotation from the two Helm values
  files and re-run `10-install-platform.sh` (or delete the Middleware CRD).
- Host layer: `sudo ufw disable`, `sudo apt remove fail2ban`, and delete
  `/etc/ssh/sshd_config.d/99-malina.conf` + restart ssh. Each step is
  reversible; the scripts never delete data.
