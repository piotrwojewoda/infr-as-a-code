#!/usr/bin/env bash
# Create or rotate the GHCR Secrets used by the malina platform (spec 004).
#
# Safe to re-run: it only touches `ghcr-pull` (namespace demo) and
# `ghcr-push` (namespace jenkins). Other platform secrets stay untouched.
#
# Required environment variables:
#   GITHUB_USER   GitHub username (package owner)
#   GITHUB_TOKEN  PAT with read:packages + write:packages
#                 (the same token may also be used for the GitOps push)
#
# Secrets are created from operator input and are NEVER written to git
# (Constitution III).
set -euo pipefail

: "${GITHUB_USER:?Set GITHUB_USER}"
: "${GITHUB_TOKEN:?Set GITHUB_TOKEN (needs read:packages + write:packages)}"

for ns in demo jenkins; do
  if ! kubectl get namespace "$ns" >/dev/null 2>&1; then
    echo "ERROR: namespace '$ns' does not exist — run 10-install-platform.sh first" >&2
    exit 1
  fi
done

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

echo "GHCR secrets updated: demo/ghcr-pull, jenkins/ghcr-push"
