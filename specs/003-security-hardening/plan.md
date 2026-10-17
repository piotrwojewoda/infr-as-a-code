# Implementation Plan: Security Hardening for the Internet-Exposed Platform

**Branch**: `003-security-hardening` | **Date**: 2026-10-17 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/003-security-hardening/spec.md`

## Summary

Harden the malina platform against internet attacks, fully as code, so that a
freshly re-flashed Pi runs one bootstrap and comes up hardened. Three layers:
(1) **proxy** — a Traefik `ipAllowList` middleware restricts the Jenkins and
ArgoCD UI paths to LAN addresses while the demo page, the GitHub webhook path
and the ACME challenge path stay public; (2) **host access** — a new bootstrap
script `05-hardening.sh` provisions the operator's SSH public key, disables
password login, installs fail2ban for sshd, configures a ufw firewall that
only allows 22/80/443 plus cluster-internal traffic, and enables unattended
security upgrades; (3) **docs** — quickstart covers validation from outside
and inside the LAN and the rebuilt-cluster acceptance run. Everything lands
in the existing bootstrap path, so rebuild = `00-install-k3s.sh` →
`05-hardening.sh` → `10-install-platform.sh` → ArgoCD sync.

## Technical Context

**Language/Version**: Bash 5 (bootstrap script), YAML (Traefik Middleware CRD,
Ingress, Helm values), fail2ban jail config, ufw rules, debconf
(unattended-upgrades)

**Primary Dependencies**: Traefik bundled with k3s (Middleware CRD
`traefik.io/v1alpha1`), ufw + fail2ban + unattended-upgrades from Debian 12
arm64 apt repositories — no new cluster components, no new images

**Storage**: N/A (all state lives in git; fail2ban/ufw state is host-local)

**Testing**: negative/positive HTTP probes from LAN and from outside the LAN,
`ssh` key-only verification, `nmap` port scan, one full pipeline run with the
firewall active (quickstart.md)

**Target Platform**: Raspberry Pi 5, Debian 12 (bookworm), ARM64, freshly
re-flashed SD card (corruption from the 2026-10-17 power cut is fixed by the
re-flash, not by this feature)

**Project Type**: infrastructure / platform hardening (GitOps)

**Performance Goals**: negligible overhead (one middleware evaluation per
restricted request; fail2ban on sshd logs only)

**Constraints**: Constitution IV (KISS) — prefer config over new components;
no secrets in git (the SSH **public** key is not a secret); cluster-internal
traffic must never be blocked; the GitHub webhook and ACME challenge paths
must stay public

**Scale/Scope**: 1 new bootstrap script, 1 new infrastructure manifest, small
edits to `jenkins-values.yaml` and `argocd-values.yaml` ingress annotations,
updates to bootstrap README/runbook

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Verdict | Evidence / Justification |
|-----------|---------|--------------------------|
| I. GitOps First | PASS | All hardening is code in this repo (bootstrap script + manifests), applied by the documented bootstrap path. No ad-hoc mutations. |
| II. Infrastructure as Code | PASS | `05-hardening.sh`, Traefik Middleware/Ingress manifests, Helm values edits — all committed. |
| III. No Secrets in Git | PASS | Only the SSH **public** key is committed (public by design). Passwords/tokens unchanged, still bootstrap-created secrets. |
| IV. Simplicity First | PASS | No new cluster component: Traefik middleware is configuration of an existing component; ufw/fail2ban/unattended-upgrades are small standard Debian packages on the host. CrowdSec, VPN, WAF appliances rejected as overkill for a homelab. |
| V. Automated Delivery | PASS (guarded) | FR-010: the test-gated pipeline (spec 002) must keep working with the firewall active — verified by quickstart scenario. |

Post-design re-check: passed (see research.md decisions D1–D6).

## Project Structure

### Documentation (this feature)

```text
specs/003-security-hardening/
├── plan.md              # This file
├── research.md          # Phase 0: decisions D1–D6
├── data-model.md        # Phase 1: exposure rules / host-access entities
├── quickstart.md        # Phase 1: validation (LAN vs internet) + rebuild runbook
├── contracts/           # Phase 1
│   ├── exposure.md      # path/port visibility matrix (public vs LAN-only)
│   └── host-hardening.md# sshd / firewall / fail2ban / updates contract
└── tasks.md             # Phase 2 output (/speckit.tasks - NOT created by /speckit.plan)
```

### Source Code (repository root = `infr-as-a-code`)

```text
.
├── clusters/malina/
│   ├── bootstrap/
│   │   ├── 00-install-k3s.sh            # unchanged
│   │   ├── 05-hardening.sh              # NEW: SSH keys-only, ufw, fail2ban,
│   │   │                                #   unattended-upgrades (runs after 00, before 10)
│   │   ├── 10-install-platform.sh       # + note pointing at 05
│   │   ├── ssh-keys/
│   │   │   └── malina-master.pub        # NEW: operator public key (not a secret)
│   │   ├── jenkins-values.yaml          # + ingress annotation: lan-only middleware
│   │   ├── argocd-values.yaml           # + ingress annotation: lan-only middleware
│   │   └── README.md                    # + hardening step in the bootstrap order
│   └── infrastructure/
│       └── traefik-security.yaml        # NEW: Middleware `lan-only` + public
│                                        #   Ingress for /jenkins/github-webhook/
└── specs/003-security-hardening/        # this feature's docs
```

**Structure Decision**: hardening lives where the existing bootstrap lives —
one new numbered script between k3s install and platform install, plus one
infrastructure manifest applied by ArgoCD with the other infrastructure
manifests. No new top-level directories.

## Complexity Tracking

No constitution violations → no justifications required.

## Phase Outputs

- Phase 0 → [research.md](./research.md) — decisions D1–D6 with alternatives.
- Phase 1 → [data-model.md](./data-model.md), [contracts/](./contracts),
  [quickstart.md](./quickstart.md).
- Phase 2 → tasks.md (created by `/speckit.tasks`).
