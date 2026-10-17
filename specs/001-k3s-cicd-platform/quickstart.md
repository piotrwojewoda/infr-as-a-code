# Quickstart: Build and Run the Platform

**Feature**: 001-k3s-cicd-platform | **Date**: 2026-10-17

## One-time bootstrap (about 30 minutes)

On the Raspberry Pi (`ssh malina-master@192.168.68.52`):

```bash
# 1. Clone this repository
git clone https://github.com/piotrwojewoda/infr-as-a-code.git
cd infr-as-a-code/clusters/malina/bootstrap

# 2. Install k3s + Helm 3
bash 00-install-k3s.sh

# 3. Install platform: cert-manager, ArgoCD, Jenkins
#    (asks for: GitHub user, GitHub PAT, database password, admin passwords)
bash 10-install-platform.sh

# 4. Point ArgoCD at this repository (app-of-apps)
kubectl apply -f ../apps/root-app.yaml
```

## Name resolution (until DNS for kreciowo.pl points to the Pi)

On every computer that should reach the platform, add to `/etc/hosts`:

```text
192.168.68.52  demo.kreciowo.pl jenkins.kreciowo.pl argocd.kreciowo.pl
```

## Daily use

| Task | Where / How |
|------|-------------|
| See the demo app | `https://kreciowo.pl` or `https://www.kreciowo.pl` (**real certificate**, home.pl) — or `https://demo.kreciowo.pl` with the dummy cert |
| Jenkins UI | `https://jenkins.kreciowo.pl` (admin password: see runbook) |
| ArgoCD UI | `https://argocd.kreciowo.pl` |
| Deploy a new app version | merge a pull request to `main` of `demo-symfony-k3s`; wait ≤ 15 min |
| Watch a deployment | `kubectl -n demo get pods -w` or the ArgoCD UI |
| Check pipeline | Jenkins UI → job `demo-symfony-k3s` |

## Get passwords (they are not in git)

```bash
kubectl -n jenkins get secret jenkins -o jsonpath='{.data.jenkins-admin-password}' | base64 -d
kubectl -n argocd  get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d
```

## Swap the dummy certificate for the real one

Two ways. Both keep the SAME secret names, so no application or ingress
changes are needed (Traefik picks up new secret content automatically).

### Option A — Let's Encrypt via cert-manager (automatic, self-renewing)

1. Make sure DNS for `*.kreciowo.pl` points to the Pi and the router forwards
   ports 80/443 to 192.168.68.52.
2. Set a real e-mail in `clusters/malina/infrastructure/cluster-issuers.yaml`
   (`letsencrypt-prod` issuer is already prepared there).
3. Change `issuerRef.name` in `clusters/malina/infrastructure/certificates.yaml`
   from `selfsigned-dummy` to `letsencrypt-prod`, commit and push.
4. `kubectl apply -f clusters/malina/infrastructure/`
5. Delete the old secrets: `kubectl -n demo delete secret kreciowo-dummy-tls`
   (same in `jenkins`; in `argocd` the secret is `argocd-server-tls`) —
   cert-manager re-issues real certificates into the same secret names.

### Option B — you already have certificate FILES (fullchain.pem + privkey.pem)

The reverse proxy does NOT read certificate files from disk — it reads
Kubernetes TLS secrets. So the files are only a transport to the cluster:

```bash
# 1. copy the files to the Pi (any temp directory)
scp fullchain.pem privkey.pem malina-master@192.168.68.52:~/

# 2. on the Pi: remove the cert-manager Certificates, so it does not
#    overwrite the secrets with the dummy cert again
kubectl -n demo    delete certificate kreciowo-dummy
kubectl -n jenkins delete certificate kreciowo-dummy
kubectl -n argocd  delete certificate kreciowo-dummy
#    (also remove clusters/malina/infrastructure/certificates.yaml from git
#     or keep it for a later return to Option A)

# 3. load the real certificate into the SAME three secrets
for ns in demo jenkins; do
  kubectl -n $ns delete secret kreciowo-dummy-tls --ignore-not-found
  kubectl -n $ns create secret tls kreciowo-dummy-tls \
    --cert=$HOME/fullchain.pem --key=$HOME/privkey.pem
done
kubectl -n argocd delete secret argocd-server-tls --ignore-not-found
kubectl -n argocd create secret tls argocd-server-tls \
  --cert=$HOME/fullchain.pem --key=$HOME/privkey.pem
```

Rules: the cert file must contain the FULL chain (domain + intermediates);
the key must be unencrypted PEM; the private key NEVER goes to git
(Constitution III). Renewal with Option B is manual — repeat step 3.

## Switch the registry to GHCR (once a token with `packages: write` exists)

1. Update the secrets: re-run the secret part of `10-install-platform.sh` with
   the new `GITHUB_TOKEN` (it re-creates `ghcr-pull` / `ghcr-push` / `jenkins-github`).
2. In `clusters/malina/values/demo-symfony.yaml`: set
   `image.repository: ghcr.io/piotrwojewoda/demo-symfony-k3s` and
   `imagePullSecrets: [{ name: ghcr-pull }]`. Commit + push.
3. In the app repo `Jenkinsfile`: set `env.IMAGE` to
   `ghcr.io/piotrwojewoda/demo-symfony-k3s`, drop the `--insecure` flag, and
   re-add the `ghcr-config` volume (see git history for the GHCR variant).
4. Delete the registry: `kubectl delete -f clusters/malina/infrastructure/registry.yaml`.

## Troubleshooting (learned during the first production run)

| Symptom | Cause | Fix |
|---------|-------|-----|
| After a HARD Pi reboot, `jenkins-0` stays `0/2 Unknown` for many minutes | k3s/containerd does not reattach the StatefulSet pod containers | `kubectl -n jenkins delete pod jenkins-0 --force --grace-period=0` — the StatefulSet recreates it in ~1 min |
| An ArgoCD app stays `Unknown` with a stale `connection refused` to the repo-server | comparison error cached while repo-server was down | `kubectl -n argocd annotate application <app> argocd.argoproj.io/refresh=hard --overwrite` |
| repo-server OOMKilled | limit too low for parallel chart renders on a small node | already fixed in `argocd-values.yaml` (1Gi) — keep it |
| Build fails with `dubious ownership in repository` | mixed uids in the Jenkins agent pod | already handled in the Jenkinsfile (`safe.directory`) |
| `docker push` to ghcr.io: `DENIED: permission_denied` | PAT lacks Packages:write | the platform uses the in-cluster registry (research.md D2); see "Switch the registry to GHCR" above |

## Rebuild everything from scratch

```bash
sudo /usr/local/bin/k3s-uninstall.sh   # wipes the cluster
# then run the bootstrap steps above again — full state returns from git
```
