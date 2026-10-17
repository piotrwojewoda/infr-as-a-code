# Feature Specification: K3s CI/CD Platform on Raspberry Pi

**Feature Branch**: `001-k3s-cicd-platform`

**Created**: 2026-10-17

**Status**: Draft

**Input**: User description: "Create a k3s cluster on a Raspberry Pi that works as a CI/CD platform. It must run Jenkins and ArgoCD. Applications must deploy after a branch is merged on GitHub. Charts are based on Helm. A demo Symfony 8 / PHP 8.5 application with a database must show a start page and nothing more. The reverse proxy on k3s must have a dummy SSL certificate for kreciowo.pl that can later be swapped for a real one. The node must expose ports 80 and 443. Everything follows best programming practices."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Working Kubernetes cluster on the Raspberry Pi (Priority: P1)

The operator runs one documented bootstrap process on the Raspberry Pi. After it
finishes, a single-node Kubernetes (k3s) cluster is running, Helm 3 is
installed, and the node serves HTTP and HTTPS traffic on ports 80 and 443
through a reverse proxy.

**Why this priority**: Nothing else can work without a running cluster. This is
the foundation for every other story.

**Independent Test**: From a computer in the same network, run
`kubectl get nodes` against the Pi and see one node in state `Ready`. Open an
HTTPS URL on the node IP and get a response from the reverse proxy (even a 404
with a valid TLS handshake proves the proxy works).

**Acceptance Scenarios**:

1. **Given** a fresh Raspberry Pi with Debian 12, **When** the operator runs the
   documented bootstrap, **Then** `kubectl get nodes` shows one `Ready` node
   within 15 minutes.
2. **Given** the running cluster, **When** the operator reboots the Pi,
   **Then** the cluster comes back automatically without manual action.

---

### User Story 2 - CI/CD tooling available on the cluster (Priority: P2)

The operator opens `https://jenkins.kreciowo.pl` and `https://argocd.kreciowo.pl`
in a browser and can log in to both tools. Both are installed from Helm charts
and their configuration is stored as code.

**Why this priority**: Jenkins and ArgoCD are the two tools the whole platform
exists for. Without them there is no CI and no CD.

**Independent Test**: Log in to Jenkins and see the main dashboard. Log in to
ArgoCD and see the application list. Both pages load over HTTPS.

**Acceptance Scenarios**:

1. **Given** the running cluster, **When** the operator opens the Jenkins URL,
   **Then** the login page appears over HTTPS and the admin can log in.
2. **Given** the running cluster, **When** the operator opens the ArgoCD URL,
   **Then** the login page appears over HTTPS and the admin can log in.
3. **Given** the tools are installed, **When** the cluster is rebuilt from
   scratch, **Then** both tools come back with the same configuration, because
   the configuration is code.

---

### User Story 3 - Demo application deploys automatically after a merge (Priority: P3)

A developer merges a pull request into `main` of the `demo-symfony-k3s`
repository on GitHub. Without any manual step, the pipeline builds a container
image, pushes it to the registry, updates the GitOps repository, and the new
version appears at `https://demo.kreciowo.pl`. The page shows the Symfony
welcome screen and nothing more.

**Why this priority**: This proves the whole platform works end to end. It is
the visible result the user asked for.

**Independent Test**: Make a small visible change in the demo repository, merge
it to `main`, wait for the pipeline, and see the change on the public URL
without touching the cluster.

**Acceptance Scenarios**:

1. **Given** a merged pull request in the demo repository, **When** the pipeline
   finishes, **Then** the start page on `https://demo.kreciowo.pl` serves the
   new version over HTTPS.
2. **Given** the demo application is deployed, **When** a visitor opens the
   start page, **Then** they see the Symfony welcome page and no other
   functionality.
3. **Given** the demo application is deployed, **When** the operator checks the
   namespace, **Then** a database pod is running next to the application and the
   application is configured to use it.

---

### User Story 4 - HTTPS with a dummy certificate that can be swapped later (Priority: P4)

All platform hostnames (`demo.kreciowo.pl`, `jenkins.kreciowo.pl`,
`argocd.kreciowo.pl`) are served over HTTPS using a dummy self-signed
certificate. The operator can later replace only the certificate issuer with a
real one, without changing any application configuration.

**Why this priority**: TLS is required for real use, but the real certificate
does not exist yet. The swap must be a one-step change.

**Independent Test**: `curl -k https://demo.kreciowo.pl` returns the page over
TLS. The certificate object in the cluster shows it comes from a self-signed
issuer. The runbook documents the swap to the real certificate in one command.

**Acceptance Scenarios**:

1. **Given** the platform is installed, **When** a client connects to any
   platform hostname on port 443, **Then** a TLS session is established with the
   dummy certificate.
2. **Given** the real certificate is ready, **When** the operator follows the
   runbook swap step, **Then** all hostnames serve the real certificate without
   changes to applications.

---

### Edge Cases

- The Pi reboots or loses power: the cluster and all workloads MUST come back
  automatically.
- The container registry is unreachable: running applications MUST keep running;
  only new deployments are blocked.
- A pipeline run fails halfway (for example image push fails): the currently
  deployed version MUST stay untouched.
- Two merges happen quickly after each other: deployments MUST apply in order;
  the last merged version wins.
- GitHub webhooks cannot reach the Pi (no port forwarding yet): the pipeline
  MUST still notice merges, at most within one minute, by polling.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The system MUST provide a single-node Kubernetes cluster on the
  Raspberry Pi that starts automatically on boot.
- **FR-002**: The system MUST expose ports 80 and 443 on the node and route
  traffic by hostname through a reverse proxy.
- **FR-003**: The system MUST serve all platform hostnames over HTTPS using a
  dummy self-signed certificate, and the certificate issuer MUST be replaceable
  without touching applications.
- **FR-004**: The system MUST run Jenkins, installed from a Helm chart, with its
  configuration defined as code.
- **FR-005**: The system MUST run ArgoCD, which watches the GitOps repository
  and applies changes automatically.
- **FR-006**: A merge to `main` in the application repository MUST trigger a
  pipeline that builds a container image and pushes it to a container registry.
  Because GitHub cannot reach the Pi from the internet yet, merge detection MAY
  use polling with an interval of one minute or less.
- **FR-007**: After a successful build, the pipeline MUST update the desired
  application version in the GitOps repository so that ArgoCD deploys it.
- **FR-008**: The demo application MUST be a Symfony 8 application running on
  PHP 8.5 that shows a start page and nothing more.
- **FR-009**: The demo application MUST be deployed together with a relational
  database in the same namespace, and the application MUST be configured to
  connect to it.
- **FR-010**: All platform and application deployments MUST be packaged as Helm
  charts.
- **FR-011**: No passwords, tokens or private keys MUST be stored in git.
- **FR-012**: The whole platform state MUST be reproducible from the GitOps
  repository plus the documented bootstrap steps.
- **FR-013**: All container images MUST run on ARM64.
- **FR-014**: The deployed application MUST show which version is running, so an
  observer can confirm that a merge reached production.

### Key Entities

- **Cluster**: the single-node k3s installation on the Raspberry Pi named
  `malina` (192.168.68.52).
- **GitOps repository**: `piotrwojewoda/infr-as-a-code` — desired cluster state
  (charts, values, ArgoCD applications, specs).
- **Application repository**: `piotrwojewoda/demo-symfony-k3s` — application
  source code, Dockerfile and pipeline definition.
- **Pipeline**: the Jenkins job that turns a merge into a deployed version.
- **Release**: one deployed version of an application, identified by the git
  commit hash of the application repository.
- **Platform hostnames**: `demo.kreciowo.pl`, `jenkins.kreciowo.pl`,
  `argocd.kreciowo.pl`.

## Success Criteria *(mandatory)*

### Measurable Criteria

- **SC-001**: From a powered-off Pi to a fully ready cluster: under 30 minutes
  with the documented bootstrap.
- **SC-002**: From a merge on GitHub to the new version visible on the public
  URL: under 15 minutes, no manual step.
- **SC-003**: After a Pi reboot, all platform services and the demo application
  are healthy again within 5 minutes, without manual action.
- **SC-004**: 100% of platform and application deployments come from Helm
  charts stored in git; zero manual installs.
- **SC-005**: Zero secrets found when scanning the git repositories.
- **SC-006**: A visitor opening the demo URL over HTTPS sees the start page with
  HTTP status 200.

## Assumptions

- The Raspberry Pi (Debian 12, ARM64, 8 GB RAM, 57 GB SD card) is dedicated to
  this platform.
- The local network is trusted; the router does not forward ports 80/443 to the
  Pi yet, so GitHub webhooks cannot reach the cluster and polling is used.
- The domain `kreciowo.pl` is owned by the operator; DNS records for the
  subdomains will point to the Pi later. For now, name resolution is done with
  local `/etc/hosts` entries.
- GitHub Container Registry (ghcr.io) is available and the provided token can
  push and pull images there.
- The demo application is intentionally minimal (start page only); the database
  is provisioned as part of the stack foundation, ready for future features.
