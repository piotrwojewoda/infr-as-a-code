# Bootstrap — cluster "malina" (Raspberry Pi 5, 192.168.68.52)

Run ONCE on the Pi (order matters):

```bash
git clone https://github.com/piotrwojewoda/infr-as-a-code.git
cd infr-as-a-code/clusters/malina/bootstrap

# 1. k3s + Helm 3
bash 00-install-k3s.sh

# 2. Platform: cert-manager + dummy certs, ArgoCD, Jenkins
export GITHUB_USER=piotrwojewoda
export GITHUB_TOKEN='<PAT with repo + packages scope>'   # not stored anywhere
export GITHUB_WEBHOOK_SECRET="$(openssl rand -hex 32)"   # same value goes into the GitHub webhook
export DB_PASSWORD="$(openssl rand -hex 16)"
export JENKINS_ADMIN_PASSWORD="$(openssl rand -hex 12)"
bash 10-install-platform.sh

# 3. GitOps: point ArgoCD at this repository
kubectl apply -f ../apps/root-app.yaml
```

What is created outside git (Constitution III):

| Secret | Namespace | Content |
|--------|-----------|---------|
| `jenkins-github` | jenkins | GitHub user + PAT (pipeline pushes) |
| `ghcr-push` | jenkins | docker config for Kaniko pushes to ghcr.io |
| `ghcr-pull` | demo | docker config for pulling app images |
| `demo-db` | demo | PostgreSQL passwords (user + admin) |
| `demo-app` | demo | `DATABASE_URL`, `APP_SECRET` |

Re-running `10-install-platform.sh` is safe (`helm upgrade --install`,
secrets applied idempotently).
