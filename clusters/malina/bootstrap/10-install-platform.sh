#!/usr/bin/env bash
# Bootstrap step 1: platform layer (cert-manager, ArgoCD, Jenkins) + secrets.
# Secrets are created from operator input and are NEVER written to git
# (Constitution III).
#
# Required environment variables:
#   GITHUB_USER            GitHub username
#   GITHUB_TOKEN           GitHub PAT with repo + packages (read/write) scope
#   DB_PASSWORD            password for the demo PostgreSQL database
#   JENKINS_ADMIN_PASSWORD initial Jenkins admin password
# Optional:
#   DOMAIN (default: kreciowo.pl)
set -euo pipefail
cd "$(dirname "$0")"

: "${GITHUB_USER:?Set GITHUB_USER}"
: "${GITHUB_TOKEN:?Set GITHUB_TOKEN}"
: "${DB_PASSWORD:?Set DB_PASSWORD}"
: "${JENKINS_ADMIN_PASSWORD:?Set JENKINS_ADMIN_PASSWORD}"
DOMAIN="${DOMAIN:-kreciowo.pl}"

CERT_MANAGER_VERSION="v1.21.2"
ARGOCD_CHART_VERSION="10.10.5"   # ArgoCD app v3.5.5
JENKINS_CHART_VERSION="5.9.69"   # Jenkins 2.580.1 LTS

echo "==> Namespaces"
for ns in cert-manager argocd jenkins demo; do
  kubectl create namespace "$ns" --dry-run=client -o yaml | kubectl apply -f -
done

echo "==> Secrets (created at runtime, never in git)"
kubectl -n jenkins create secret generic jenkins-github \
  --from-literal=username="$GITHUB_USER" \
  --from-literal=token="$GITHUB_TOKEN" \
  --dry-run=client -o yaml | kubectl apply -f -

GHCR_AUTH=$(printf '%s:%s' "$GITHUB_USER" "$GITHUB_TOKEN" | base64 | tr -d '\n')
GHCR_CFG=$(printf '{"auths":{"ghcr.io":{"username":"%s","password":"%s","auth":"%s"}}}' \
  "$GITHUB_USER" "$GITHUB_TOKEN" "$GHCR_AUTH")
# pull secret for application pods (demo) ...
kubectl -n demo create secret generic ghcr-pull \
  --type=kubernetes.io/dockerconfigjson \
  --from-literal=.dockerconfigjson="$GHCR_CFG" \
  --dry-run=client -o yaml | kubectl apply -f -
# ... and push config for Kaniko build pods (jenkins)
kubectl -n jenkins create secret generic ghcr-push \
  --type=kubernetes.io/dockerconfigjson \
  --from-literal=.dockerconfigjson="$GHCR_CFG" \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl -n demo create secret generic demo-db \
  --from-literal=password="$DB_PASSWORD" \
  --from-literal=postgres-password="$DB_PASSWORD" \
  --dry-run=client -o yaml | kubectl apply -f -

APP_SECRET_VAL="${APP_SECRET:-$(openssl rand -hex 16)}"
kubectl -n demo create secret generic demo-app \
  --from-literal=DATABASE_URL="postgresql://demo:${DB_PASSWORD}@demo-postgresql:5432/demo?serverVersion=18&charset=utf8" \
  --from-literal=APP_SECRET="$APP_SECRET_VAL" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "==> Helm repositories"
helm repo add jetstack https://charts.jetstack.io >/dev/null
helm repo add argo https://argoproj.github.io/argo-helm >/dev/null
helm repo add jenkinsci https://charts.jenkins.io >/dev/null
helm repo add bitnami https://charts.bitnami.com/bitnami >/dev/null
helm repo update >/dev/null

echo "==> cert-manager ${CERT_MANAGER_VERSION}"
helm upgrade --install cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --version "$CERT_MANAGER_VERSION" \
  --set crds.enabled=true \
  --wait --timeout 5m

echo "==> ClusterIssuers + dummy TLS certificates"
kubectl apply -f ../infrastructure/cluster-issuers.yaml
kubectl apply -f ../infrastructure/certificates.yaml
for ns in demo jenkins argocd; do
  kubectl -n "$ns" wait --for=condition=Ready certificate --all --timeout=180s
done

echo "==> ArgoCD (chart ${ARGOCD_CHART_VERSION})"
helm upgrade --install argocd argo/argo-cd \
  --namespace argocd \
  --version "$ARGOCD_CHART_VERSION" \
  -f argocd-values.yaml \
  --wait --timeout 8m

echo "==> Jenkins (chart ${JENKINS_CHART_VERSION})"
helm upgrade --install jenkins jenkinsci/jenkins \
  --namespace jenkins \
  --version "$JENKINS_CHART_VERSION" \
  -f jenkins-values.yaml \
  --set controller.admin.password="$JENKINS_ADMIN_PASSWORD" \
  --wait --timeout 10m

echo "==> Traefik: redirect HTTP -> HTTPS"
kubectl apply -f ../infrastructure/traefik-config.yaml

cat <<EOF

============================================================
PLATFORM INSTALLED
============================================================
  ArgoCD:  https://argocd.${DOMAIN}
           user: admin
           password: kubectl -n argocd get secret argocd-initial-admin-secret \\
             -o jsonpath='{.data.password}' | base64 -d
  Jenkins: https://jenkins.${DOMAIN}
           user: admin, password: the one passed to this script
  Demo:    https://demo.${DOMAIN} (after the first pipeline run)

Next step (GitOps):
  kubectl apply -f ../apps/root-app.yaml
============================================================
EOF
