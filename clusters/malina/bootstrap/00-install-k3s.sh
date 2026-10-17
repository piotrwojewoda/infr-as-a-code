#!/usr/bin/env bash
# Bootstrap step 0: install k3s + Helm 3 on the Raspberry Pi.
# Idempotent: safe to re-run. Requires sudo.
set -euo pipefail

echo "==> Installing k3s (server, default Traefik on 80/443)"
if ! command -v k3s >/dev/null 2>&1; then
  curl -sfL https://get.k3s.io -o /tmp/k3s-install.sh
  sudo sh /tmp/k3s-install.sh --write-kubeconfig-mode 644
else
  echo "    k3s already installed: $(k3s --version | head -1)"
fi

echo "==> Waiting for node to become Ready"
until sudo k3s kubectl get nodes 2>/dev/null | grep -q ' Ready'; do sleep 5; done
sudo k3s kubectl get nodes

echo "==> Installing Helm 3"
if ! helm version --short 2>/dev/null | grep -q '^v3'; then
  curl -sfL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | sudo -E bash
fi
helm version --short

echo "==> Kubeconfig for user $USER"
mkdir -p "$HOME/.kube"
sudo cp /etc/rancher/k3s/k3s.yaml "$HOME/.kube/config"
sudo chown "$USER:$USER" "$HOME/.kube/config"

echo "==> Done. kubectl get nodes:"
kubectl get nodes -o wide
