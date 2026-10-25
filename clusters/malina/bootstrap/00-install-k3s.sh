#!/usr/bin/env bash
# Bootstrap step 0: install k3s + Helm 3 on the Raspberry Pi.
# Idempotent: safe to re-run. Requires sudo.
#
# Fresh-image prerequisites handled here (Debian 12/13 on Raspberry Pi 5):
#   1. kernel memory cgroup — k3s refuses to start without it
#      (fatal: "failed to find memory cgroup (v2)"). Fix: append
#      "cgroup_memory=1 cgroup_enable=memory" to the kernel cmdline, reboot.
#      If this script changes the cmdline it stops and asks for the reboot;
#      just run it again afterwards.
#   2. iptables — without it the k3s installer warns
#      "Host iptables-save/iptables-restore tools not found" and the pod
#      network NAT cannot be programmed.
set -euo pipefail

echo "==> Host prerequisites (memory cgroup, iptables)"
CMDLINE_FILE=""
for f in /boot/firmware/cmdline.txt /boot/cmdline.txt; do
  [ -f "$f" ] && CMDLINE_FILE="$f" && break
done
if [ -n "$CMDLINE_FILE" ] && ! grep -q cgroup_memory "$CMDLINE_FILE"; then
  echo "    enabling memory cgroup in $CMDLINE_FILE"
  sudo sed -i 's/$/ cgroup_memory=1 cgroup_enable=memory/' "$CMDLINE_FILE"
  echo "    *** kernel cmdline changed — run 'sudo reboot', then re-run this script ***"
  exit 0
fi
# NOTE: /usr/sbin is not on PATH in non-login shells — check the binary directly.
if ! command -v iptables >/dev/null 2>&1 && [ ! -x /usr/sbin/iptables ]; then
  echo "    installing iptables"
  sudo apt-get update -qq
  sudo apt-get install -y -qq iptables
fi

echo "==> Installing k3s (server, default Traefik on 80/443)"
if ! command -v k3s >/dev/null 2>&1; then
  curl -sfL https://get.k3s.io -o /tmp/k3s-install.sh
  sudo sh /tmp/k3s-install.sh --write-kubeconfig-mode 644
else
  echo "    k3s already installed: $(k3s --version | head -1)"
fi

# SQLite compaction has a 5s default timeout. On a Raspberry Pi SD card,
# image pulls and Rancher's first-boot writes can exceed it. database/sql then
# rolls the transaction back and kine's MustCommit exits the whole k3s process.
# KINE_COMPACT_TIMEOUT is read by kine also when embedded in k3s.
KINE_OVERRIDE="/etc/systemd/system/k3s.service.d/90-kine.conf"
if ! sudo grep -qx 'Environment=KINE_COMPACT_TIMEOUT=5m' "$KINE_OVERRIDE" 2>/dev/null; then
  echo "==> Datastore resilience: KINE_COMPACT_TIMEOUT=5m"
  printf '[Service]\nEnvironment=KINE_COMPACT_TIMEOUT=5m\n' | sudo tee "$KINE_OVERRIDE" >/dev/null
  sudo systemctl daemon-reload
  sudo systemctl restart k3s
fi

echo "==> Waiting for node to become Ready"
until sudo k3s kubectl get nodes 2>/dev/null | grep -q ' Ready'; do sleep 5; done
sudo k3s kubectl get nodes

echo "==> Installing Helm 3"
if ! helm version --short 2>/dev/null | grep -q '^v3'; then
  # The download can fail on a freshly booted Pi (network not fully up) — retry.
  for attempt in 1 2 3; do
    curl -sfL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | sudo -E bash && break
    echo "    helm install attempt ${attempt} failed — retrying in 10s"
    sleep 10
  done
fi
helm version --short

echo "==> Kubeconfig for user $USER"
mkdir -p "$HOME/.kube"
sudo cp /etc/rancher/k3s/k3s.yaml "$HOME/.kube/config"
sudo chown "$USER:$USER" "$HOME/.kube/config"

echo "==> Done. kubectl get nodes:"
kubectl get nodes -o wide
