# Contract: Host Hardening (`05-hardening.sh`)

**Feature**: 003-security-hardening | **Date**: 2026-10-17

The bootstrap script `clusters/malina/bootstrap/05-hardening.sh` MUST do the
following, in this order. It is idempotent: re-running it on an already
hardened host is a no-op that reports OK.

## 1. SSH key provisioning (before any sshd change)

- Install every `*.pub` file from `clusters/malina/bootstrap/ssh-keys/` into
  `/home/<operator>/.ssh/authorized_keys` (user: `malina-master`), mode
  `700` on `.ssh`, `600` on `authorized_keys`, no duplicates on re-run.
- **Lockout guard**: the script MUST prove that a public key is present and
  structurally valid (`ssh-keygen -lf`) for the operator account before
  proceeding. If not, it aborts with a clear message and changes nothing.

## 2. sshd configuration

`/etc/ssh/sshd_config.d/99-malina.conf` MUST set exactly:

```text
PasswordAuthentication no
KbdInteractiveAuthentication no
PermitRootLogin no
```

Then validate with `sshd -t` and restart SSH (Debian 12: restart
`ssh.socket` if socket-activated, else `ssh.service`).

## 3. Brute-force protection

- Install `fail2ban`.
- Provide a jail for `sshd` with: `maxretry = 5`, `findtime = 10m`,
  `bantime = 1h`, backend `systemd`.
- Enable and start fail2ban.

## 4. Firewall (ufw)

- Install `ufw` and apply, in this order:
  1. `default deny incoming`, `default allow outgoing`
  2. allow `22/tcp`, `80/tcp`, `443/tcp` from anywhere
  3. allow `30500/tcp` from `192.168.0.0/16`
  4. allow all traffic on `lo`
  5. allow all traffic to/from the pod network `10.42.0.0/16` and the
     service network `10.43.0.0/16`
  6. allow traffic on interfaces `cni0` and `flannel*` (any direction)
  7. allow `8472/udp` and `10250/tcp` from `192.168.0.0/16`
  8. allow forwarding between the pod CIDR and the node (so ServiceLB DNAT
     works); do NOT set a global "allow routed" policy
- Enable ufw (non-interactive, `ufw --force enable`).
- **Never** run `ufw reset` on an existing install (idempotency: add rules
  only if missing).

## 5. Automatic security updates

- Install `unattended-upgrades`.
- Enable the Debian `security` origin only.
- Automatic reboot MUST stay disabled (`Automatic-Reboot "false"`).
- Enable and start the service.

## 6. Report

The script ends by printing a summary: authorized key fingerprints, sshd
effective values (`sshd -T | grep -E 'passwordauthentication|permitrootlogin'`),
`ufw status verbose`, `fail2ban-client status sshd`, and the
unattended-upgrades state.

## Non-goals

- No Traefik-level rate limiting or CrowdSec (rejected in research D1/D5).
- No change to the operator account password (SSH no longer accepts it; a
  runbook note recommends changing it for sudo use).
- No multi-node firewall automation (single node; rules merely keep a second
  node possible).
