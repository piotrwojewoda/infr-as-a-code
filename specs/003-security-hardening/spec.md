# Feature Specification: Security Hardening for the Internet-Exposed Platform

**Feature Branch**: `003-security-hardening`

**Created**: 2026-10-17

**Status**: Draft

**Input**: User description: "Malina is visible from the internet — install
protections against attacks." Confirmed scope: only ports 80/443 are forwarded
to the Pi. Jenkins and ArgoCD UIs become LAN-only (stakeholder decision). The
demo page and the GitHub webhook endpoint stay public. SSH gets key-only login
with the operator's `id_malina.pub` key.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Admin UIs unreachable from the internet (Priority: P1)

Today anyone on the internet can open the Jenkins and ArgoCD login pages.
After this change, a request from a non-LAN address to the Jenkins or ArgoCD
URLs is rejected at the reverse proxy before it ever reaches the
applications. From inside the home network both UIs work exactly as before.
The demo start page stays public, and GitHub can still deliver webhooks to
Jenkins, because those two paths are the reason the platform is exposed at
all.

**Why this priority**: the login pages are the biggest attack surface —
browsers, scanners and credential-stuffing bots hit them constantly. Closing
them removes almost all of the practical risk without removing any operator
workflow (the operator manages the cluster from home).

**Independent Test**: from a network outside the home LAN (e.g. a phone on
mobile data), open `https://kreciowo.pl/jenkins/` and
`https://kreciowo.pl/argocd/` — both are rejected. From the LAN both open
normally. A GitHub webhook delivery still triggers a pipeline run.

**Acceptance Scenarios**:

1. **Given** a client on the internet, **When** it requests
   `https://kreciowo.pl/jenkins/` or `https://kreciowo.pl/argocd/`, **Then**
   the reverse proxy rejects the request (HTTP 403) without forwarding it to
   the application.
2. **Given** a client on the home LAN, **When** it requests the same URLs,
   **Then** the login pages load normally.
3. **Given** any internet client, **When** it requests the demo start page
   (`https://demo.kreciowo.pl/`) or GitHub posts to
   `https://kreciowo.pl/jenkins/github-webhook/`, **Then** both succeed.
4. **Given** the future real certificate setup, **When** the certificate
   authority performs the HTTP-01 challenge on
   `/.well-known/acme-challenge/`, **Then** that path is still publicly
   reachable (the hardening must not break the planned certificate swap).

---

### User Story 2 - SSH accepts keys only (Priority: P2)

The host account uses a weak password and password login is enabled. After
this change, the operator's `id_malina.pub` public key is authorized on the
host and password authentication is disabled. Repeated failed login attempts
get the source address temporarily banned. The operator logs in from the
MacBook without typing a password; password guessing no longer works at all.

**Why this priority**: SSH is only reachable from the LAN today, but the
weak password plus password login is a standing risk the moment port 22 ever
gets forwarded — by mistake or by a router change. Keys remove the whole
class of brute-force attacks.

**Independent Test**: `ssh malina-master@192.168.68.52` with the private key
logs in without a password prompt. The same attempt with key auth forced off
(`ssh -o PubkeyAuthentication=no`) is rejected before any password prompt.

**Acceptance Scenarios**:

1. **Given** the operator's MacBook with the private key, **When** it opens
   an SSH session to the Pi, **Then** the login succeeds without a password
   prompt.
2. **Given** any client without the key, **When** it tries to log in,
   **Then** the server offers only publickey authentication (no password
   prompt at all).
3. **Given** repeated failed SSH login attempts from one address, **When**
   the threshold is crossed, **Then** that address is temporarily banned by
   the brute-force protection.

---

### User Story 3 - Host firewall and automatic patching (Priority: P3)

The host has no firewall and no automatic security updates. After this
change, the host accepts inbound traffic only on the documented platform
ports (22, 80, 443) and for cluster-internal traffic, and the operating
system installs security updates automatically.

**Why this priority**: defense in depth — even though the router currently
forwards only 80/443, the firewall makes that guarantee local to the Pi, so
a router misconfiguration or a future exposed service cannot silently widen
the attack surface.

**Independent Test**: a port scan of the Pi from the LAN shows only 22, 80
and 443 open; the cluster keeps working (pods communicate, ArgoCD syncs,
pipelines run) and the update service is active.

**Acceptance Scenarios**:

1. **Given** the firewall is active, **When** the host is scanned from the
   LAN, **Then** only ports 22, 80 and 443 answer.
2. **Given** the firewall is active, **When** the cluster runs a full
   pipeline (build → tests → deploy), **Then** everything works exactly as
   before (no blocked cluster-internal traffic).
3. **Given** the running host, **When** a security update is published,
   **Then** it is installed automatically without operator action.

---

### Edge Cases

- The GitHub webhook path (`/jenkins/github-webhook/`) MUST stay public;
  GitHub posts from changing IP ranges, so no IP restriction is possible
  there — it is already protected by the shared-secret signature check.
- The ACME HTTP-01 challenge path (`/.well-known/acme-challenge/`) MUST stay
  public for the planned real certificate.
- The operator locks themselves out of SSH (lost key): recovery is physical
  access to the Pi — documented in the runbook.
- A client on the LAN with a spoofed User-Agent is irrelevant — the
  restriction is by source address, not headers.
- Kubernetes internal traffic (pods, services, localhost) MUST NOT be
  affected by the firewall rules.
- Since spec 004 there is no registry on the node: images come from GitHub
  Container Registry over outbound HTTPS, so no extra inbound port is needed.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: Requests to the Jenkins and ArgoCD URL paths from non-LAN
  source addresses MUST be rejected at the reverse proxy with HTTP 403
  before reaching the applications. Local network addresses (private ranges,
  including the home `192.168.68.0/24`) MUST be allowed.
- **FR-002**: The Jenkins GitHub webhook path MUST remain reachable from any
  address.
- **FR-003**: The demo start page and the ACME HTTP-01 challenge path MUST
  remain reachable from any address.
- **FR-004**: SSH on the host MUST allow public-key authentication only;
  password authentication MUST be disabled. The operator's `id_malina.pub`
  key MUST be provisioned by the bootstrap, not by hand.
- **FR-005**: Repeated SSH authentication failures from one source MUST lead
  to a temporary ban of that source (brute-force protection).
- **FR-006**: The host MUST run a firewall that accepts inbound traffic only
  on ports 22, 80 and 443 plus documented cluster-internal traffic, and
  denies everything else inbound.
- **FR-007**: The firewall MUST NOT break Kubernetes networking (pods,
  services, node-local registry, localhost); a full pipeline run and an
  ArgoCD sync MUST succeed with the firewall active.
- **FR-008**: The host operating system MUST install security updates
  automatically.
- **FR-009**: Every hardening measure MUST exist as code in this repository
  (bootstrap script and/or manifests) and MUST be applied through the
  documented bootstrap path — a rebuilt cluster comes up hardened with zero
  manual steps.
- **FR-010**: The hardening MUST NOT weaken existing guarantees: HTTPS
  everywhere, no secrets in git, single-command pipeline, test gate intact.

### Key Entities

- **Public paths**: the demo start page, the GitHub webhook endpoint, the
  ACME challenge path — reachable from any source address.
- **Restricted paths**: the Jenkins and ArgoCD UIs — reachable only from
  local network addresses.
- **Host access rules**: SSH = key-only + brute-force bans; firewall =
  allow-list on 22/80/443; updates = automatic.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: 100% of requests from the internet to the Jenkins and ArgoCD
  URLs receive HTTP 403; the same requests from the LAN succeed.
- **SC-002**: GitHub webhook deliveries keep triggering pipelines (a test
  merge deploys end to end exactly as before).
- **SC-003**: An SSH login attempt without the key is rejected without a
  password prompt; a scripted burst of failed attempts results in a ban.
- **SC-004**: A port scan of the host finds exactly 3 open TCP ports
  (22, 80, 443); all others are closed or filtered.
- **SC-005**: A cluster rebuilt from the repository passes SC-001..SC-004
  with no manual hardening step.

## Assumptions

- The router forwards only ports 80 and 443 to the Pi (confirmed by the
  operator, 2026-10-17); SSH is LAN-only today, but it gets the same
  hardening as if it were exposed.
- The operator manages the platform only from the home network; no remote
  access to the admin UIs is needed (confirmed by the stakeholder).
- The home LAN uses private address space (`192.168.68.0/24`); allowing all
  RFC1918 ranges is acceptable and simpler than one exact subnet.
- The weak host account password stays in use only for local sudo; SSH no
  longer accepts it. Changing it is recommended in the runbook.
- The current filesystem corruption on the SD card (caused by a power cut,
  per the operator) is handled separately by the rebuild; this feature only
  ensures the rebuilt system comes up hardened.
