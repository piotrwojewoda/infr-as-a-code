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
| See the demo app | `https://demo.kreciowo.pl` (accept the dummy certificate) |
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

1. Make sure DNS for `*.kreciowo.pl` points to the Pi and the router forwards
   ports 80/443 to 192.168.68.52.
2. `kubectl apply -f clusters/malina/infrastructure/cluster-issuers.yaml`
   (the `letsencrypt-prod` issuer is already prepared there).
3. Change `issuerRef.name` in `clusters/malina/infrastructure/certificates.yaml`
   from `selfsigned-dummy` to `letsencrypt-prod`, commit and push.
4. Delete the old secrets: `kubectl -n demo delete secret kreciowo-dummy-tls`
   (same in `jenkins` and `argocd`) — cert-manager re-issues real certificates.

## Rebuild everything from scratch

```bash
sudo /usr/local/bin/k3s-uninstall.sh   # wipes the cluster
# then run the bootstrap steps above again — full state returns from git
```
