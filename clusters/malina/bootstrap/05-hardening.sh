#!/usr/bin/env bash
# Bootstrap step 0.5: host hardening (spec 003-security-hardening).
#
# Order on a fresh Pi:
#   bash 00-install-k3s.sh && bash 05-hardening.sh && bash 10-install-platform.sh
#
# Idempotent: re-running is safe and never deletes anything.
# Contract: specs/003-security-hardening/contracts/host-hardening.md
set -euo pipefail
cd "$(dirname "$0")"

# The script needs root for sshd/ufw/fail2ban/apt; re-exec with sudo.
[ "$(id -u)" -eq 0 ] || exec sudo -E bash "$0" "$@"

# Default matches the operator account created by Raspberry Pi Imager.
OPERATOR_USER="${OPERATOR_USER:-malina}"
OPERATOR_HOME="$(getent passwd "$OPERATOR_USER" | cut -d: -f6)"
export DEBIAN_FRONTEND=noninteractive

echo "==> 1/6 SSH public keys for ${OPERATOR_USER}"
mkdir -p "$OPERATOR_HOME/.ssh"
chmod 700 "$OPERATOR_HOME/.ssh"
touch "$OPERATOR_HOME/.ssh/authorized_keys"
chmod 600 "$OPERATOR_HOME/.ssh/authorized_keys"
KEY_COUNT=0
for key in ssh-keys/*.pub; do
  [ -e "$key" ] || continue
  ssh-keygen -lf "$key" >/dev/null   # structural validation; aborts on garbage
  grep -qxF "$(cat "$key")" "$OPERATOR_HOME/.ssh/authorized_keys" \
    || cat "$key" >> "$OPERATOR_HOME/.ssh/authorized_keys"
  KEY_COUNT=$((KEY_COUNT + 1))
done
chown -R "$OPERATOR_USER:$OPERATOR_USER" "$OPERATOR_HOME/.ssh"
# Lockout guard: never disable password login without at least one valid key.
if [ "$KEY_COUNT" -eq 0 ] || ! grep -q . "$OPERATOR_HOME/.ssh/authorized_keys"; then
  echo "ERROR: no valid public key installed for ${OPERATOR_USER} — refusing to disable password login" >&2
  exit 1
fi
echo "    ${KEY_COUNT} key(s) authorized:"
ssh-keygen -lf "$OPERATOR_HOME/.ssh/authorized_keys" | sed 's/^/    /' || true

echo "==> 2/6 sshd: public-key only"
cat > /etc/ssh/sshd_config.d/99-malina.conf <<'EOF'
PasswordAuthentication no
KbdInteractiveAuthentication no
PermitRootLogin no
EOF
/usr/sbin/sshd -t
if systemctl is-enabled ssh.socket >/dev/null 2>&1; then
  systemctl restart ssh.socket
else
  systemctl restart ssh.service
fi

echo "==> 3/6 fail2ban (sshd jail)"
apt-get update -qq
apt-get install -y -qq fail2ban ufw unattended-upgrades
cat > /etc/fail2ban/jail.d/sshd-malina.conf <<'EOF'
[sshd]
enabled = true
backend = systemd
maxretry = 5
findtime = 10m
bantime = 1h
EOF
systemctl enable --now fail2ban
systemctl reload-or-restart fail2ban

echo "==> 4/6 firewall (ufw) — contract §4"
ufw default deny incoming
ufw default allow outgoing
ufw allow 22/tcp comment 'ssh'
ufw allow 80/tcp comment 'http'
ufw allow 443/tcp comment 'https'
ufw allow in on lo comment 'loopback'
ufw allow out on lo comment 'loopback'
# k3s internals — never block cluster traffic (FR-007)
ufw allow from 10.42.0.0/16 comment 'k3s pod network'
ufw allow to 10.42.0.0/16 comment 'k3s pod network'
ufw allow from 10.43.0.0/16 comment 'k3s service network'
ufw allow to 10.43.0.0/16 comment 'k3s service network'
ufw allow in on cni0 comment 'k3s cni' 2>/dev/null || true
ufw allow out on cni0 comment 'k3s cni' 2>/dev/null || true
ufw allow from 192.168.0.0/16 to any port 8472 proto udp comment 'flannel vxlan'
ufw allow from 192.168.0.0/16 to any port 10250 proto tcp comment 'kubelet'
# ServiceLB DNAT forwards external traffic into the pod network — allow that
# forwarding explicitly instead of a global "allow routed" policy
ufw route allow from 10.42.0.0/16 comment 'pod return traffic'
ufw route allow to 10.42.0.0/16 comment 'external DNAT to pods'
ufw --force enable

echo "==> 5/6 unattended security upgrades (no auto-reboot)"
cat > /etc/apt/apt.conf.d/20auto-upgrades <<'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
EOF
cat > /etc/apt/apt.conf.d/51malina-unattended <<'EOF'
Unattended-Upgrade::Origins-Pattern {
        "origin=Debian,codename=${distro_codename},label=Debian-Security";
};
Unattended-Upgrade::Automatic-Reboot "false";
EOF
systemctl enable --now unattended-upgrades

echo "==> 6/6 summary"
echo "--- authorized key fingerprints"
ssh-keygen -lf "$OPERATOR_HOME/.ssh/authorized_keys" | sed 's/^/    /' || true
echo "--- sshd effective settings"
/usr/sbin/sshd -T 2>/dev/null | grep -E '^(passwordauthentication|kbdinteractiveauthentication|permitrootlogin) ' | sed 's/^/    /'
echo "--- ufw"
ufw status verbose | sed 's/^/    /'
echo "--- fail2ban"
fail2ban-client status sshd | sed 's/^/    /'
echo "--- unattended-upgrades"
systemctl is-enabled unattended-upgrades | sed 's/^/    /'
echo "HARDENING DONE"
