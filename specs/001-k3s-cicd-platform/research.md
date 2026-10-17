# Phase 0 Research: Technology Decisions

**Feature**: 001-k3s-cicd-platform | **Date**: 2026-10-17

Every decision below was checked against the constitution. "Verified" means the
fact was tested against the real environment on 2026-10-17.

## D1 — Reverse proxy: bundled Traefik

- **Decision**: Use the Traefik ingress controller that k3s installs by default.
  It binds node ports 80 and 443 through the k3s ServiceLB (Klipper).
- **Alternatives**: ingress-nginx (extra install, no benefit on one node);
  HAProxy on the host (outside the cluster, breaks GitOps rule).
- **Why**: Constitution IV (Simplicity). One less component to install and
  maintain. Traefik reads standard `Ingress` objects, so applications stay
  portable.

## D2 — Container registry: in-cluster `registry:2` (fallback), GHCR later

- **Decision (updated 2026-10-17)**: Run `registry:2` in the cluster
  (namespace `registry`, PVC, **NodePort 30500** on the node). Kaniko pushes
  over plain HTTP (`--insecure`); containerd pulls through a `mirrors` entry
  in `/etc/rancher/k3s/registries.yaml` (written by the bootstrap script).
  Image reference: `192.168.68.52:30500/<app>:<tag>`. No authentication —
  LAN-only homelab exposure.
- **Original decision**: GHCR (`ghcr.io/piotrwojewoda/<app>`). Verified
  `docker login ghcr.io` succeeded with the operator PAT — but the first real
  push failed: the fine-grained PAT lacks the Packages:write scope and PATs
  cannot be extended via API.
- **Why the fallback**: zero external dependencies, fastest pulls on the LAN,
  no token-scope blockers. The operator chose this option explicitly.
- **Swap path**: when a token with `packages: write` exists, change
  `image.repository` in `clusters/malina/values/demo-symfony.yaml` and the
  `env.IMAGE` constant in the app repo's `Jenkinsfile`, re-create the
  `ghcr-pull`/`ghcr-push` secrets, and remove the registry Deployment
  (documented in quickstart.md).
- **Alternatives rejected**: Docker Hub (rate limits on ARM pulls); waiting
  for a new token (blocks the whole platform).

## D3 — Image builds inside the cluster: Kaniko

- **Decision**: Jenkins agents build images with Kaniko
  (`gcr.io/kaniko-project/executor:v1.24.0-debug`, multi-arch, ARM64 verified
  to exist) in a Kubernetes pod. No Docker daemon access is needed.
- **Alternatives**: mount the host `docker.sock` into build pods — works on
  this Pi (Docker 27 exists on the host) but gives builds root-equivalent
  access to the node; bad practice. k3s containerd has no docker socket.
- **Why**: Daemonless, unprivileged build is the accepted best practice for
  Kubernetes CI. The `-debug` variant provides a shell for pipeline steps.

## D4 — Merge trigger: SCM polling now, webhook later

- **Decision**: Jenkins polls the application repository every minute
  (`* * * * *` on the job). The runbook documents how to switch to a GitHub
  webhook once the router forwards ports to the Pi.
- **Alternatives**: expose Jenkins through a tunnel (extra dependency, new
  attack surface); do nothing until the router is configured (no automatic
  trigger at all).
- **Why**: GitHub cannot reach the Pi today (no port forwarding, verified with
  the user). Polling meets FR-006 with zero external dependencies.

## D5 — TLS: cert-manager with a self-signed ClusterIssuer (dummy), real one prepared

- **Decision**: Install cert-manager v1.21 (verified latest). Create a
  `selfsigned` ClusterIssuer for dummy certificates (one `Certificate` per
  platform namespace, all for the `*.kreciowo.pl` + `kreciowo.pl` names).
  Ship a ready (but inactive) `letsencrypt-prod` ClusterIssuer manifest for the
  later swap. Ingresses reference the TLS secret by name, so the swap changes
  only the issuer, not the applications.
- **Alternatives**: hand-made openssl secret (no renewal path, harder swap);
  Traefik default certificate (no per-hostname control).
- **Why**: Meets FR-003 exactly: dummy now, one-step swap later.

## D6 — Database: Bitnami PostgreSQL chart as its own ArgoCD app

- **Decision**: PostgreSQL 18 (Bitnami Helm chart 18.12.4, verified on the Pi),
  deployed by ArgoCD
  as a separate application (`demo-postgres`) in the `demo` namespace, with a
  PVC on `local-path`. Credentials come from a bootstrap-created secret
  (`auth.existingSecret`), not from git.
- **Alternatives**: CloudNativePG operator (best-in-class, but an extra
  operator for one demo database — rejected by Constitution IV); MySQL/MariaDB
  (no advantage; PostgreSQL is the common Symfony choice); SQLite (not a real
  client-server database).
- **Why**: Bitnami chart is mature, supports ARM64, and keeps the demo stack
  simple and declarative.

## D7 — Jenkins: official Helm chart + Configuration as Code

- **Decision**: Jenkins LTS from the `jenkinsci` Helm chart in namespace
  `jenkins`. Plugins (kubernetes, workflow-job, git, configuration-as-code,
  job-dsl, credentials-binding) and the demo pipeline job are defined in
  `jenkins-values.yaml` (JCasC + Job DSL seed) in git. The GitHub token is
  injected from a Kubernetes Secret created by the bootstrap script; JCasC only
  references the environment variables.
- **Alternatives**: hand-clicked configuration (breaks Constitution II);
  GitHub Actions instead of Jenkins (user requirement is Jenkins on k3s).
- **Why**: Verified chart and images are multi-arch (ARM64). Rebuild from
  scratch gives the same Jenkins.

## D8 — Platform vs applications ownership

- **Decision**: Two layers. (a) Platform layer — k3s, cert-manager, ArgoCD,
  Jenkins — installed by `clusters/malina/bootstrap/` scripts. (b) Application
  layer — PostgreSQL, demo app, issuers/certificates — managed by ArgoCD from
  `clusters/malina/` (app-of-apps: `root-app.yaml` → child apps). The demo app
  uses an ArgoCD *multi-source* application: chart from `charts/demo-symfony`
  plus environment values from `clusters/malina/values/demo-symfony.yaml`, so
  Jenkins only has to update one small values file (`image.tag`) per release.
- **Alternatives**: ArgoCD manages everything including itself and Jenkins
  (circular bootstrap problem, more failure modes); umbrella Helm chart with
  dependencies (couples app and database releases).
- **Why**: Clear ownership, no circular dependency, and the pipeline contract
  stays one file. Constitution check re-run after this design: all gates PASS.

## Verified facts used above

| Fact | Check | Result |
|------|-------|--------|
| Pi hardware/OS | ssh probe | Pi 5, Debian 12, 4 CPU, 8 GB RAM, 34 GB free, arm64 |
| k3s install | live run | v1.36.5+k3s1, node `Ready` |
| Helm | live run | v3.22.1 installed |
| GHCR auth with PAT | `docker login` on Pi | succeeded |
| PHP 8.5 image | Docker Hub API | `php:8.5-apache-trixie`, arm64 present |
| Symfony 8 | Packagist | v8.1.9 (2026-10-12), requires PHP ≥ 8.4.1 |
| Kaniko | GitHub releases | v1.24.0, ARM64 images published |
| cert-manager | GitHub releases | v1.21.2 |
| ArgoCD | GitHub releases | v3.5.5 |
| Router | user input | no port forwarding to the Pi yet |
