# Tasks: Security Hardening for the Internet-Exposed Platform

**Input**: Design documents from `/specs/003-security-hardening/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md,
contracts/ (exposure.md, host-hardening.md), quickstart.md

**Organization**: grouped by user story. Execution order note: the hardening
script (US2/US3) and the proxy rules (US1) are independent of each other and
land in the same commit. Live validation happens ONCE, on the rebuilt cluster
(current card is corrupted — see spec Assumptions), so all "verify on the
cluster" tasks sit in the final phase.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: US1..US3 from spec.md

---

## Phase 1: Setup

- [x] T001 Copy the operator's public key `~/.ssh/id_malina.pub` from the MacBook into `clusters/malina/bootstrap/ssh-keys/malina-master.pub` (public key is not a secret — constitution III OK; research D3)

---

## Phase 2: User Story 1 — Admin UIs unreachable from the internet (Priority: P1) 🎯 MVP

**Goal**: `/jenkins` and `/argocd` return 403 from the internet, work from
LAN; webhook + demo + ACME paths stay public.

**Independent Test**: quickstart.md Scenarios B and C (outside vs LAN probes).

- [x] T002 [US1] Write `clusters/malina/infrastructure/traefik-security.yaml`: Middleware CRD `lan-only` (`traefik.io/v1alpha1`, `ipAllowList` sourceRange `192.168.0.0/16`, `10.0.0.0/8`, `172.16.0.0/12`) in namespace `kube-system`; plus a public Ingress `jenkins-github-webhook` in namespace `jenkins` for host `kreciowo.pl`, path prefix `/jenkins/github-webhook/`, backend service `jenkins:8080`, TLS secret `kreciowo-tls`, NO middleware (contracts/exposure.md)
- [x] T003 [P] [US1] Edit `clusters/malina/bootstrap/jenkins-values.yaml`: add ingress annotation `traefik.ingress.kubernetes.io/router.middlewares: "kube-system-lan-only@kubernetescrd"` (keeps existing ingress for `/jenkins`; webhook path now served by the public Ingress from T002 — longest prefix wins)
- [x] T004 [P] [US1] Edit `clusters/malina/bootstrap/argocd-values.yaml`: add the same middleware annotation to the server ingress
- [x] T005 [US1] Edit `clusters/malina/bootstrap/10-install-platform.sh`: add `kubectl apply -f ../infrastructure/traefik-security.yaml` next to the other infrastructure applies

---

## Phase 3: User Story 2 — SSH accepts keys only (Priority: P2)

**Goal**: key-only SSH on the host, provisioned by the bootstrap, with a
lockout guard.

**Independent Test**: quickstart.md Scenario D.

- [x] T006 [US2] Write `clusters/malina/bootstrap/05-hardening.sh` — executable, `set -euo pipefail`, idempotent; part 1: install all `ssh-keys/*.pub` into `/home/malina-master/.ssh/authorized_keys` (700/600, no duplicates), abort unless at least one key validates via `ssh-keygen -lf` (lockout guard per contracts/host-hardening.md §1); part 2: write `/etc/ssh/sshd_config.d/99-malina.conf` with exactly `PasswordAuthentication no`, `KbdInteractiveAuthentication no`, `PermitRootLogin no`, then `sshd -t` and restart ssh (socket or service, detect both)

---

## Phase 4: User Story 3 — Host firewall and automatic patching (Priority: P3)

**Goal**: ufw allow-list on 22/80/443 (+ cluster internals), fail2ban sshd
jail, unattended security upgrades without auto-reboot.

**Independent Test**: quickstart.md Scenario E (port scan + full pipeline
with firewall active).

- [x] T007 [US3] Extend `clusters/malina/bootstrap/05-hardening.sh` — part 3: install + configure `fail2ban` (sshd jail: `maxretry = 5`, `findtime = 10m`, `bantime = 1h`, backend `systemd`); part 4: install + configure `ufw` exactly per contracts/host-hardening.md §4 (default deny incoming / allow outgoing; 22,80,443 anywhere; `lo`; pod CIDR `10.42.0.0/16`; service CIDR `10.43.0.0/16`; `cni0`/`flannel*` interfaces; `8472/udp` + `10250/tcp` from LAN; forwarding between pod CIDR and node; NO global allow-routed; add-only idempotent rules, `ufw --force enable`); part 5: install + configure `unattended-upgrades` (security origin only, `Automatic-Reboot "false"`); part 6: final report (key fingerprints, `sshd -T` grep, `ufw status verbose`, `fail2ban-client status sshd`, updates state). *The original `30500/tcp` rule was removed by spec 004 (GHCR).*
- [x] T008 [P] [US3] Update `clusters/malina/bootstrap/README.md`: bootstrap order `00` → `05` → `10`, what `05-hardening.sh` does, SSH key rotation note, monthly reboot check (`/var/run/reboot-required`, research D6)
- [x] T009 [P] [US3] Add one-line pointer comment at the top of `clusters/malina/bootstrap/10-install-platform.sh`: "run `05-hardening.sh` before this script on a fresh host"

---

## Phase 5: Live validation on the rebuilt cluster (after the operator re-flashes the SD card)

- [ ] T010 Run quickstart.md Scenario A (fresh card → three scripts → everything up, no manual fix)
- [ ] T011 Run quickstart.md Scenarios B + C (403 from outside for `/jenkins` + `/argocd`; demo 200; webhook merge deploys end to end — also re-validates the spec-002 test gate, FR-010)
- [ ] T012 Run quickstart.md Scenario D (key login works; `PubkeyAuthentication=no` rejected; fail2ban bans after 6 failures)
- [ ] T013 Run quickstart.md Scenario E (`nmap` shows 22/80/443; full pipeline + ArgoCD sync succeed with ufw active; unattended-upgrades enabled, auto-reboot false)
- [ ] T014 [P] Secrets scan of changed files + final review against contracts/exposure.md matrix (constitution III; every public path listed in the contract)

---

## Dependencies & Execution Order

1. T001 (key file) — first, T006 needs it.
2. Phase 2 (US1) ∥ Phase 3 (US2): different files; T005 touches the script US2/US3 also reference only in README order — no real conflict.
3. T006 → T007 (same file `05-hardening.sh`, sequential sections).
4. T008 ∥ T009 (docs) — after T006/T007 so the docs describe reality.
5. Phase 5 — after the operator re-flashes and runs the bootstrap (Scenario A first, then B–E).

### Parallel Opportunities

- T002 ∥ T003 ∥ T004 (three different files)
- T003/T004 ∥ T006 (proxy vs host, different files)
- T008 ∥ T009 (two different doc files)

## Implementation Strategy

MVP = Phases 1–2 (US1: the internet-facing surface closes). US2 and US3 are
independent increments in the same commit. Phase 5 is the acceptance gate on
the rebuilt malina — the feature is "done" only when all quickstart scenarios
pass on the fresh card.
