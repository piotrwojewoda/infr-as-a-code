#!/usr/bin/env bash
# Apply Jenkins-only configuration changes without touching platform Secrets.
# Use this instead of re-running 10-install-platform.sh for values-only updates.
set -euo pipefail
cd "$(dirname "$0")"

JENKINS_CHART_VERSION="5.9.69"

helm repo add jenkinsci https://charts.jenkins.io >/dev/null
helm repo update jenkinsci >/dev/null

# --reuse-values preserves runtime-only values, including the admin password
# originally supplied with --set by 10-install-platform.sh.
helm upgrade --install jenkins jenkinsci/jenkins \
  --namespace jenkins \
  --version "$JENKINS_CHART_VERSION" \
  --reuse-values \
  -f jenkins-values.yaml \
  --wait=false

# A failed old pod can block the StatefulSet from advancing to the new pod
# template. Recreate only the controller pod; its PVC and all Secrets remain.
kubectl -n jenkins delete pod jenkins-0 --ignore-not-found
kubectl -n jenkins rollout status statefulset/jenkins --timeout=10m
