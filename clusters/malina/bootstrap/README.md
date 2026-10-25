# Bootstrap — cluster "malina" (Raspberry Pi 5, 192.168.68.52)

> **Rebuilding from an empty SD card? Start with [FROM-SCRATCH.md](FROM-SCRATCH.md)**
> — the complete verified walkthrough (flashing, kernel cgroups, pitfalls).

Run ONCE on the Pi (order matters):

```bash
git clone https://github.com/piotrwojewoda/infr-as-a-code.git
cd infr-as-a-code/clusters/malina/bootstrap

# 1. k3s + Helm 3
bash 00-install-k3s.sh

# 2. Host hardening: SSH keys-only, ufw, fail2ban, unattended upgrades
#    (spec 003 — run this BEFORE the platform; your SSH key must be in
#    ssh-keys/ first or the script aborts on purpose)
bash 05-hardening.sh

# 3. Platform: cert-manager + dummy certs, ArgoCD, Jenkins
#    Images are pushed to and pulled from GitHub Container Registry (GHCR) —
#    no registry runs on this Pi (spec 004).
export GITHUB_USER=piotrwojewoda
export GITHUB_TOKEN='<classic PAT: repo + write:packages>'   # classic only — GHCR does not accept fine-grained PATs; not stored anywhere
export GITHUB_WEBHOOK_SECRET="$(openssl rand -hex 32)"   # same value goes into the GitHub webhook
export DB_PASSWORD="$(openssl rand -hex 16)"
export JENKINS_ADMIN_PASSWORD="$(openssl rand -hex 12)"
bash 10-install-platform.sh

# 4. GitOps: point ArgoCD at this repository
#    This also deploys Rancher and the disabled-by-default kube-burner config.
kubectl apply -f ../apps/root-app.yaml
```

What is created outside git (Constitution III):

| Secret | Namespace | Content |
|--------|-----------|---------|
| `jenkins-github` | jenkins | GitHub user + PAT (pipeline pushes) |
| `ghcr-push` | jenkins | docker config for Kaniko pushes to ghcr.io |
| `ghcr-pull` | demo | docker config for pulling private app images from ghcr.io |

Rotate the two GHCR Secrets without touching the other secrets:

```bash
cd clusters/malina/bootstrap
GITHUB_USER=piotrwojewoda GITHUB_TOKEN='<PAT>' bash ghcr-secrets.sh
```

Install/renew a real certificate, one per domain — `kreciowo.pl`,
`bibop.pl` (files from the operator, never from git):

```bash
cat kreciowo.pl.certificate.pem kreciowo.pl.intermediate.pem > fullchain.pem
bash real-cert.sh kreciowo.pl fullchain.pem privkey.pem
```
| `demo-db` | demo | PostgreSQL passwords (user + admin) |
| `demo-app` | demo | `DATABASE_URL`, `APP_SECRET` |

Re-running `10-install-platform.sh` is safe (`helm upgrade --install`,
secrets applied idempotently).

## Hardening notes (spec 003)

- `05-hardening.sh` installs the public keys from `ssh-keys/*.pub` for the
  operator account, disables password SSH login, enables fail2ban (sshd),
  configures ufw (inbound: 22/80/443 + cluster-internal only) and turns on
  automatic Debian security updates (no auto-reboot).
- Key rotation: replace the file in `ssh-keys/`, commit, re-run
  `05-hardening.sh`. Removing a key deletes nothing — remove the line from
  `~/.ssh/authorized_keys` by hand if a key must be revoked.
- The admin UIs (`/jenkins`, `/argocd`, `rancher.kreciowo.pl`) are LAN-only
  after the platform is installed; the demo page and
  `/jenkins/github-webhook/` stay public.
  Details: `specs/003-security-hardening/contracts/exposure.md`.
- Security updates install automatically, but the host never reboots itself:
  check `cat /var/run/reboot-required` monthly and reboot when asked.
- The old in-cluster registry (NodePort 30500) is gone since spec 004. If an
  older install still runs it, follow
  `specs/004-ghcr-image-hosting/quickstart.md` step 3 (delete the namespace,
  the containerd mirror and the ufw rule).
- Lockout recovery: if all SSH keys are lost, log in physically on the Pi
  and delete `/etc/ssh/sshd_config.d/99-malina.conf`, then `systemctl
  restart ssh.socket` (or `ssh.service`).
