# From a bare Raspberry Pi to a working platform

This document describes how to rebuild the **malina** cluster from zero:
from an empty SD card to a running k3s cluster with ArgoCD, Jenkins,
cert-manager, Rancher, on-demand load testing and the demo application deployed
by GitOps.

> **This is a living runbook.** Every change to the platform (bootstrap
> scripts, pinned versions, secrets flow, network, TLS) MUST update this
> document in the same commit (repository rule, see `AGENTS.md`).

The base procedure was executed and verified on a real rebuild
(2026-10-25, Debian 13 "trixie", Raspberry Pi 5 8 GB). Rancher and kube-burner
were added later through GitOps; run the checks in §8 after their first sync.
The pitfalls listed in each step are real errors we hit — do not skip the checks.

Time needed: about 60–75 minutes (mostly downloads and image pulls).

---

## 0. What you need

| Thing | Details |
|-------|---------|
| Hardware | Raspberry Pi 5, 8 GB RAM, good SD card (A2 class) or USB SSD |
| OS image | Debian 13 "trixie" arm64, flashed with Raspberry Pi Imager |
| Network | LAN; the Pi must get the fixed IP `192.168.68.52` (DHCP reservation on the router) |
| Operator machine | macOS/Linux with an SSH keypair: `~/.ssh/id_malina` + `~/.ssh/id_malina.pub` |
| GitHub account | `piotrwojewoda`, with a **classic** PAT (see §6 for the exact scopes) |

> **Constitution I**: after this procedure, one ArgoCD sync must rebuild the
> whole platform. No manual `kubectl`/`helm` changes outside these scripts.

---

## 1. Flash the OS

1. Raspberry Pi Imager → choose **Debian (13 trixie, arm64)**.
2. In the Imager settings (gear icon) set:
   - hostname: `malina-master`
   - user: **`malina`** + a temporary password (used only for first contact;
     password SSH login is disabled in step 5)
   - Wi-Fi or skip (prefer Ethernet), enable SSH with password auth.
3. Boot the Pi, find its IP on the router, and add a **DHCP reservation** so
   the Pi always gets `192.168.68.52`.

> Pitfall: the platform docs and scripts assume the operator account
> `malina`. If you create a different user in the Imager, pass
> `OPERATOR_USER=<name>` to `05-hardening.sh`.

---

## 2. First contact — install the SSH key

From the operator machine (the password is asked once):

```bash
ssh-copy-id -i ~/.ssh/id_malina.pub malina@192.168.68.52
ssh -i ~/.ssh/id_malina malina@192.168.68.52 'id'   # must print uid=...(malina)
```

The public key must also be committed in this repository at
`clusters/malina/bootstrap/ssh-keys/malina-master.pub` — `05-hardening.sh`
refuses to disable password login without at least one valid key from that
directory (lockout guard).

> Pitfall: `Permission denied (publickey,password)` means you used the wrong
> user (e.g. `malina-master` — that is the **hostname**, not the account) or
> the key is not installed yet.

Optional, for unattended runs of the bootstrap scripts (they call `sudo`
many times). Remove this file again in step 8:

```bash
ssh -i ~/.ssh/id_malina malina@192.168.68.52
echo '<password>' | sudo -S sh -c \
  'echo "malina ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/90-malina-bootstrap && chmod 440 /etc/sudoers.d/90-malina-bootstrap'
```

---

## 3. Clone this repository on the Pi

```bash
git clone https://github.com/piotrwojewoda/infr-as-a-code.git ~/infr-as-a-code
cd ~/infr-as-a-code/clusters/malina/bootstrap
```

---

## 4. k3s + Helm 3

```bash
bash 00-install-k3s.sh
```

The script first fixes two **mandatory** host prerequisites (idempotently):

1. **Kernel memory cgroup.** A fresh Debian image does not enable it, and
   k3s dies with `fatal: failed to find memory cgroup (v2)`. The script
   appends `cgroup_memory=1 cgroup_enable=memory` to
   `/boot/firmware/cmdline.txt` (one line — never add a second line) and
   stops with `*** run 'sudo reboot', then re-run this script ***`.
   Reboot and run the script again.
2. **iptables.** Without it the k3s installer prints
   `Host iptables-save/iptables-restore tools not found`; the script
   installs the package.

Then it installs k3s (server, bundled Traefik on 80/443), waits for the
node to become `Ready`, installs Helm 3 and copies the kubeconfig to
`~/.kube/config`.

Expected result:

```
NAME           STATUS   ROLES          VERSION
malina-master  Ready    control-plane  v1.36.x+k3s1
```

> Pitfall: right after the first boot the Helm download can fail
> (`Failed to install helm`) because the network is not fully up. The
> script retries 3 times; if it still fails, just run it again — it is
> idempotent.

---

## 5. Host hardening

```bash
bash 05-hardening.sh        # uses OPERATOR_USER=malina by default
```

Installs the committed SSH public keys, disables password SSH login
(`PasswordAuthentication no`), enables **fail2ban** (sshd jail),
configures **ufw** (deny incoming by default; allows 22/80/443 and the
cluster-internal networks only) and turns on automatic Debian security
updates (no auto-reboot). The script prints a full summary at the end
(`HARDENING DONE`).

From now on only key-based SSH works. Keep your private key safe —
recovery without it needs physical access (see `README.md`, lockout
recovery).

---

## 6. Platform: cert-manager + ArgoCD + Jenkins

### 6.1 GitHub token

Create a **classic** PAT at
<https://github.com/settings/tokens/new?scopes=repo,write:packages>
(Settings → Developer settings → Personal access tokens → **Tokens
(classic)**). GHCR does not support fine-grained tokens for pushes — the
`Packages` permission exists only on classic tokens.

| Scope | Why |
|-------|-----|
| `write:packages` (+ `read:packages`) | Kaniko pushes images to `ghcr.io`; the cluster pulls them (spec 004) |
| `repo` | Jenkins pushes GitOps tag bumps to `infr-as-a-code` and clones the app repo |
| `delete:packages` (optional) | cleanup of old image versions |

> Pitfall: with a token that lacks these scopes,
> `curl -H "Authorization: Bearer <PAT>"
> https://api.github.com/user/packages?package_type=container` returns
> **403 "Resource not accessible by personal access token"** and the first
> pipeline push fails with `denied`. After creating a proper token, rotate
> the on-cluster secrets with `ghcr-secrets.sh` and re-apply the
> `jenkins-github` secret (see `README.md`).

### 6.2 Run the installer

Secrets come from operator input only — **never** write them to git
(Constitution III). Example (values are generated on the Pi and shown
once; store them in your password manager):

```bash
cd ~/infr-as-a-code/clusters/malina/bootstrap
export GITHUB_USER=piotrwojewoda
export GITHUB_TOKEN='<PAT from 6.1>'
export GITHUB_WEBHOOK_SECRET="$(openssl rand -hex 32)"   # same value later in the GitHub webhook
export DB_PASSWORD="$(openssl rand -hex 16)"
export JENKINS_ADMIN_PASSWORD="$(openssl rand -hex 12)"
echo "$GITHUB_WEBHOOK_SECRET $DB_PASSWORD $JENKINS_ADMIN_PASSWORD"   # save these NOW
bash 10-install-platform.sh
```

The script creates namespaces and secrets, then installs with Helm
(each with `--wait`, on a Pi this takes 10–20 minutes total):

1. cert-manager + ClusterIssuers + one dummy TLS certificate
   (`demo.kreciowo.pl` only — the apex hosts use the real cert, step 8.5),
2. ArgoCD (`argocd-values.yaml`),
3. Jenkins (`jenkins-values.yaml`, admin password from the env var),
4. Traefik config: HTTPS redirect, LAN-only admin UIs, public
   `/jenkins/github-webhook/` route (spec 003).

---

## 7. GitOps hand-over

```bash
kubectl apply -f ~/infr-as-a-code/clusters/malina/apps/root-app.yaml
```

The root application watches `clusters/malina/apps/` in this repository
and deploys everything found there (app-of-apps), including Rancher and the
kube-burner configuration. The load-test Job itself is disabled by default.
From this moment the cluster is managed by git: **every change is a commit**,
never a manual `kubectl`/`helm` edit.

---

## 8. After the install

1. **Remove the temporary sudo NOPASSWD** (if you created it in step 2):
   `sudo rm /etc/sudoers.d/90-malina-bootstrap`
2. **Change the temporary password** of the `malina` account
   (`passwd`) — it was only needed for first contact.
3. Admin UIs (LAN-only, spec 003):
   - Jenkins: `https://kreciowo.pl/jenkins` — user `admin`, password =
     `JENKINS_ADMIN_PASSWORD` from step 6.2,
   - ArgoCD: `https://kreciowo.pl/argocd` — user `admin`, password:
     `kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d`
     (change it in the UI afterwards, then delete that secret).
   - Rancher: `https://rancher.kreciowo.pl` — user `admin`, generated initial
     password: `kubectl -n cattle-system logs -l app=rancher | grep -i 'Bootstrap Password:'`.
     Set a permanent password in the UI and store it in a password manager.
     The `local` k3s cluster is registered automatically.
4. DNS/hosts: point `kreciowo.pl` (and optionally `www.`) and
   `rancher.kreciowo.pl` to `192.168.68.52`; forward ports 80/443 on the
   router for the public site. Rancher remains LAN-only through Traefik.
5. Install the real certificates (bought at home.pl, one per domain —
   `kreciowo.pl` and `bibop.pl`, each covering apex + `www` only):
   concatenate `certificate.pem` + `intermediate.pem` into `fullchain.pem`,
   then on the Pi
   `bash clusters/malina/bootstrap/real-cert.sh DOMAIN fullchain.pem privkey.pem`.
   `demo.kreciowo.pl` stays on the self-signed dummy cert (no wildcard).
   **Renewal**: same command with the new files (check the expiry with
   `openssl s_client -connect 192.168.68.52:443 -servername kreciowo.pl`).
6. GitHub webhook on the app repository:
   `https://kreciowo.pl/jenkins/github-webhook/`, content type
   `application/json`, secret = `GITHUB_WEBHOOK_SECRET` from step 6.
7. Push a commit to the app's `main` → Jenkins tests → builds → pushes to
   `ghcr.io/piotrwojewoda/...` → bumps `image.tag` in this repo → ArgoCD
   deploys → **the final `Deploy` stage confirms the rollout** (spec 005:
   green build == the new pod is live; watch with
   `kubectl -n demo get pods -w`).

### Optional: run a Kubernetes load test

Use [spec 009 quickstart](../../../specs/009-rancher-load-testing/quickstart.md).
In short: enable the Job and give it a new `runID` in
`clusters/malina/values/kube-burner.yaml`, commit and push, then read
`kubectl -n load-testing logs job/kube-burner-<runID>`. The default five pods
consume CPU for 60 seconds and kube-burner deletes the `kube-burner-load`
namespace. Disable the Job through git after collecting its logs. Never start
an ad-hoc load Job outside GitOps.

### Verification checklist

| Check | Command | Expected |
|-------|---------|----------|
| Node | `kubectl get nodes` | `Ready` |
| Platform pods | `kubectl get pods -A` | all `Running` (cert-manager, argocd, jenkins, rancher) |
| Ingress ports | `nc -zv 192.168.68.52 80` / `443` | open |
| Firewall | `sudo ufw status` | only 22, 80, 443 + cluster-internal |
| Old registry | `nc -zv 192.168.68.52 30500` | **refused** (gone since spec 004) |
| ArgoCD apps | `kubectl -n argocd get applications` | `root-app` + children, `Synced/Healthy` |
| Rancher | `kubectl -n cattle-system get deploy rancher` | `AVAILABLE 1`; UI works only from LAN |
| Load test default | `kubectl -n load-testing get jobs` | `No resources found` (Job is opt-in) |
| Elasticsearch | `kubectl -n demo get elasticsearch demo` | `Ready`, health `green` |
| ES authentication | password `kubectl -n demo get secret demo-es-elastic-user -o jsonpath='{.data.elastic}' \| base64 -d` | `curl --cacert demo-es-http-certs-public/ca.crt -u elastic:… https://demo-es-http:9200` returns version 9.5.5 |
| App ↔ ES | `curl -s https://kreciowo.pl/api/elastic` | `{"status":"ok","cluster":"demo","version":"9.5.5"}` |
| Search demo | open `https://kreciowo.pl/search?q=malina` | result cards + hit count |
| ES secrets mounted | `kubectl -n demo exec deploy/demo-symfony -- ls /etc/es-credentials /etc/es-ca` | `elastic`, `ca.crt` |
| Pipeline | push to app repo `main` | build green incl. `Deploy` stage + new demo pod from `ghcr.io` |

---

## 9. Current state (as built on 2026-10-25)

Pinned versions (source of truth: bootstrap and ArgoCD applications):

| Component | Version |
|-----------|---------|
| k3s | v1.36.5+k3s1 (Traefik bundled, 80/443 on the node) |
| Helm | 3.22.x |
| cert-manager | v1.21.2 |
| ArgoCD | chart 10.10.5 (app v3.5.5) |
| Jenkins | chart 5.9.69 (2.580.1 LTS) |
| Prometheus | chart 29.38.0 (v3.15.1), retention 24h, PVC 2 Gi (spec 006) |
| Grafana | chart 10.5.15 (12.3.1), PVC 500 Mi (spec 006) |
| ECK operator | chart 3.5.0, ns `elastic-system` (spec 007) |
| Elasticsearch | 9.5.5, single node, heap 512 MB, PVC 4 Gi, ns `demo` (spec 007) |
| Rancher | chart 2.15.2 (app v2.15.2), one replica, ns `cattle-system` (spec 009) |
| kube-burner | v2.8.6, opt-in Job, ns `load-testing` (spec 009) |
| Load-test workload | BusyBox 1.37.0, five CPU pods for 60s by default (spec 009) |

Platform URLs (specs 003 and 009):

| URL | Access | TLS secret (namespace) |
|-----|--------|------------------------|
| `https://kreciowo.pl/` + `www.` | public | `kreciowo-tls` (demo) — REAL cert |
| `https://bibop.pl/` + `www.` | public | `bibop-tls` (demo) — REAL cert |
| `https://kreciowo.pl/jenkins` | LAN only | `kreciowo-tls` (jenkins) — REAL cert |
| `https://kreciowo.pl/jenkins/github-webhook/` | public (GitHub) | `kreciowo-tls` (jenkins) |
| `https://kreciowo.pl/argocd` | LAN only | `argocd-server-tls` (argocd) — REAL cert |
| `https://kreciowo.pl/grafana` | LAN only | `kreciowo-tls` (monitoring) — REAL cert |
| `https://rancher.kreciowo.pl` | LAN only | `tls-rancher-ingress` (cattle-system) — self-signed |
| `https://demo.kreciowo.pl` | public | `kreciowo-dummy-tls` (demo) — self-signed |
| `https://kreciowo.pl/search` | public | `kreciowo-tls` (demo) — REAL cert (spec 008) |
| `https://kreciowo.pl/api/elastic` | public | JSON: `status`, cluster name, ES version (spec 008) |

Both apex domains serve the same demo-symfony app (one ingress, multiple
hosts — see `clusters/malina/values/demo-symfony.yaml`).

Secrets created by bootstrap (names only — values never in git):

| Secret | Namespace | Rotated with |
|--------|-----------|--------------|
| `jenkins-github` (user + PAT + webhook secret) | jenkins | re-apply via kubectl / re-run 10-install-platform.sh |
| `ghcr-push` (docker config) | jenkins | `ghcr-secrets.sh` |
| `ghcr-pull` (docker config) | demo | `ghcr-secrets.sh` |
| `demo-db`, `demo-app` | demo | re-run 10-install-platform.sh with new env |
| `kreciowo-tls` ×3, `argocd-server-tls` | demo, jenkins, monitoring, argocd | `real-cert.sh kreciowo.pl …` |
| `grafana-admin` | monitoring | re-run 10-install-platform.sh with `GRAFANA_ADMIN_PASSWORD` |
| `demo-es-elastic-user` (ES password) | demo | auto-generated by ECK — rotate: `kubectl -n demo get secret demo-es-elastic-user -o jsonpath='{.data.elastic}' \| base64 -d` |
| `bibop-tls` | demo | `real-cert.sh bibop.pl …` |
| `tls-rancher-ingress`, `tls-rancher` | cattle-system | generated by Rancher/cert-manager |

Regular maintenance:

- **GitHub PAT rotation/expiry**: `ghcr-secrets.sh` + re-apply `jenkins-github`.
- **Certificate renewal** (home.pl DV, ~6-month validity): `real-cert.sh`.
- **OS**: security updates install automatically; the Pi never reboots
  itself — check `cat /var/run/reboot-required` monthly.
- **Re-running bootstrap is safe**: all scripts are idempotent
  (`helm upgrade --install`, secrets applied declaratively).

---

## 10. Troubleshooting — real failures and their fixes

| Symptom | Cause | Fix |
|---------|-------|-----|
| `k3s.service` fails, log says `failed to find memory cgroup (v2)` | fresh image lacks memory cgroup | step 4: cmdline flags + reboot |
| `Host iptables-save/iptables-restore tools not found` | iptables not installed | step 4: `apt-get install iptables` |
| `Failed to install helm` right after first boot | network not fully up | re-run `00-install-k3s.sh` |
| `Permission denied (publickey,password)` on SSH | wrong user or key not installed | user is `malina`; do step 2 |
| Kaniko push `denied` / 403 on `/user/packages` | PAT lacks **Packages: read+write** | step 6.1, then `ghcr-secrets.sh` |
| demo pod `ImagePullBackOff`, message `... ghcr.io/...: not found` | image not pushed to GHCR yet | run the pipeline once (step 8.7) |
| Browser warns about TLS on `kreciowo.pl` | real cert not installed yet | step 8.5 (`real-cert.sh`) |
| Grafana: „no data", datasource error | datasource URL ≠ actual Service name (chart 29.x names the server from `server.fullnameOverride`, NOT the root one) | keep `prometheus.server.fullnameOverride: prometheus-server` in `charts/monitoring/values.yaml` in sync with the datasource URL |
| ArgoCD app with an external Helm chart stuck in `Unknown` / `failed to pull OCI chart` | `repoURL` written without scheme (`helm.elastic.co`) — ArgoCD treats it as an OCI registry | always write the full URL: `https://helm.elastic.co` |
| `/search` says „Search is temporarily unavailable", `/api/elastic` → 503 | ECK Secrets not created yet / ES not Ready / password rotated | wait for `kubectl -n demo get elasticsearch demo` = Ready; secrets are mounted `optional: true`, the app recovers without a restart |
| ArgoCD app `elasticsearch` shows **Progressing** while the CR is `Ready` | cluster health `yellow`: a replica can never be assigned on a single node, so one shard stays unassigned | app creates/repairs indices with `number_of_replicas: 0` (index template `demo-documents`); manual fix: `PUT /documents/_settings {"index":{"number_of_replicas":0}}` |
| ECK condition `ResourcesAwareManagement=False` | `requests.memory` ≠ `limits.memory` in the ES pod template | harmless on this size — set them equal in `charts/elasticsearch/values.yaml` if you want memory-aware node roles |
| `demo-symfony` pod stuck `CreateContainerConfigError` | a mounted Secret is missing **and** was made mandatory | keep both ES volumes `optional: true` in `charts/demo-symfony/templates/deployment.yaml` |
| Everything lost (SD died) | — | start again at step 1; git + this document rebuild all |

---

## 11. What is NOT in git (by design)

- GitHub PAT, webhook secret, DB and Jenkins passwords
  (Kubernetes Secrets created by `10-install-platform.sh`).
- The real TLS certificate + key for `kreciowo.pl`
  (installed by `real-cert.sh` from operator files).
- The operator's private SSH key.
- Rancher bootstrap/permanent admin passwords and generated TLS private keys.

Rebuild rule (Constitution I): **flash → steps 1–7 → one ArgoCD sync =
the whole platform back.**
