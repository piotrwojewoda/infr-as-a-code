# Tasks: K3s CI/CD Platform on Raspberry Pi

**Input**: Design documents from `/specs/001-k3s-cicd-platform/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/

**Organization**: Tasks are grouped by user story. Execution order note: US4
(TLS) is executed right after US1, because the ingresses in US2 need the dummy
certificate. US3 (the pipeline) comes last because it needs US1+US2+US4.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: US1..US4 from spec.md

---

## Phase 1: Setup (Shared Infrastructure)

- [x] T001 Create repository layout in `infr-as-a-code`: `clusters/malina/{bootstrap,infrastructure,apps,values}`, `charts/demo-symfony`, `.gitignore` (must exclude any `*secret*.yaml` local files, `.env.local`, `vendor/`)
- [x] T002 [P] Write root `README.md` (platform overview, links to specs, quickstart)
- [x] T003 [P] Write `AGENTS.md` (repo conventions for agents: GitOps flow, no-secrets rule, how to bump a release)

---

## Phase 2: User Story 1 — K3s cluster on the Pi (Priority: P1) 🎯 MVP

**Goal**: one `Ready` k3s node, Helm 3, Traefik on ports 80/443.

**Independent Test**: `kubectl get nodes` → `Ready`; TLS handshake on 443 works.

- [x] T004 [US1] Write `clusters/malina/bootstrap/00-install-k3s.sh` (install k3s with `--write-kubeconfig-mode 644`, wait for Ready, install Helm 3, copy kubeconfig to the user)
- [x] T005 [US1] Run `00-install-k3s.sh` on the Pi and verify: `kubectl get nodes` shows `malina Ready`
- [ ] T006 [US1] Add Traefik global HTTP→HTTPS redirect via `HelmChartConfig` in `clusters/malina/infrastructure/traefik-config.yaml` and apply it; verify port 80 and 443 answer

**Checkpoint**: `curl -k https://192.168.68.52` returns a Traefik response (404 default backend) over TLS.

---

## Phase 3: User Story 4 — Dummy TLS certificate (Priority: P4, executed early)

**Goal**: cert-manager issues dummy self-signed certs for `*.kreciowo.pl`; swap path documented.

**Independent Test**: `kubectl -n demo get certificate` → `Ready=True`; `curl -k https://demo.kreciowo.pl` uses the dummy cert.

- [ ] T007 [US4] Install cert-manager via Helm (namespace `cert-manager`, CRDs enabled) inside `clusters/malina/bootstrap/10-install-platform.sh`
- [ ] T008 [US4] Write `clusters/malina/infrastructure/cluster-issuers.yaml`: `selfsigned-dummy` ClusterIssuer (active) + `letsencrypt-prod` ClusterIssuer (prepared for the swap)
- [ ] T009 [US4] Write `clusters/malina/infrastructure/certificates.yaml`: one `Certificate` (`kreciowo.pl` + `*.kreciowo.pl`) per namespace `demo`, `jenkins`, `argocd` → secret `kreciowo-dummy-tls`; apply and verify `Ready`

**Checkpoint**: TLS secret `kreciowo-dummy-tls` exists in the three namespaces.

---

## Phase 4: User Story 2 — Jenkins + ArgoCD as code (Priority: P2)

**Goal**: both tools reachable over HTTPS, configured from git.

**Independent Test**: login to `https://jenkins.kreciowo.pl` and `https://argocd.kreciowo.pl`; wipe and rebuild → same configuration.

- [ ] T010 [P] [US2] Write `clusters/malina/bootstrap/argocd-values.yaml` (server insecure behind proxy, ingress `argocd.kreciowo.pl` + TLS secret, resource limits for 8 GB Pi)
- [ ] T011 [P] [US2] Write `clusters/malina/bootstrap/jenkins-values.yaml` (JCasC: plugins kubernetes/workflow-job/git/configuration-as-code/job-dsl/credentials-binding; Job DSL seed for `demo-symfony-k3s` pipeline with SCM poll `* * * * *`; credential from env `GITHUB_USER`/`GITHUB_TOKEN`; ingress `jenkins.kreciowo.pl` + TLS; PVC 8Gi; resources fitted to the Pi)
- [ ] T012 [US2] Write `clusters/malina/bootstrap/10-install-platform.sh`: namespaces, secrets from operator input (`jenkins-github`, `ghcr-pull`, `demo-db`, `demo-app`), helm installs for cert-manager/ArgoCD/Jenkins, apply infrastructure manifests
- [ ] T013 [US2] Run the platform install on the Pi; verify all pods `Running` in `cert-manager`, `argocd`, `jenkins`
- [ ] T014 [US2] Write `clusters/malina/apps/root-app.yaml` (app-of-apps) and apply it; verify ArgoCD shows child apps
- [ ] T015 [US2] Verify HTTPS login pages for Jenkins and ArgoCD (accept dummy cert)

**Checkpoint**: both UIs work over HTTPS; `root-app` is `Healthy`/`Synced`.

---

## Phase 5: User Story 3 — Demo app deploys after merge (Priority: P3)

**Goal**: merge → Jenkins → ghcr → GitOps bump → ArgoCD → new version on `https://demo.kreciowo.pl`.

**Independent Test**: change the start page text, merge to `main`, see it live without touching the cluster.

- [x] T016 [US3] Scaffold Symfony 8 skeleton in `demo-symfony-k3s` (PHP `>=8.5`, twig, doctrine/orm + pgsql, apache-pack); add `HomeController` (`/` start page showing Symfony + PHP version, deployed image tag, DB status line; `/healthz` for probes)
- [x] T017 [P] [US3] Write `Dockerfile` (multi-stage: `composer:2` + `php:8.5-cli` vendor stage → `php:8.5-apache-trixie` runtime, `APP_ENV=prod`, document root `public/`) + `.dockerignore` in `demo-symfony-k3s`
- [x] T018 [P] [US3] Write `Jenkinsfile` in `demo-symfony-k3s`: Kaniko pod (kaniko + git containers) → build/push `ghcr.io/piotrwojewoda/demo-symfony-k3s:<sha>` + `:latest` → bump `image.tag` in `clusters/malina/values/demo-symfony.yaml` → commit + push
- [x] T019 [US3] Write Helm chart `charts/demo-symfony/` (deployment with env `DATABASE_URL`/`APP_SECRET`/`APP_VERSION` from secret + tag, probes via `/healthz`, service :80, ingress `demo.kreciowo.pl` + TLS, imagePullSecrets `ghcr-pull`, resources per data-model)
- [x] T020 [US3] Write `clusters/malina/values/demo-symfony.yaml` with initial `image.tag: latest` and `clusters/malina/apps/demo-postgres.yaml` + `clusters/malina/apps/demo-symfony.yaml` (multi-source contract from contracts/gitops.md)
- [ ] T021 [US3] Push both repositories to GitHub; run the Jenkins job once manually for the first image; verify ArgoCD syncs and `https://demo.kreciowo.pl` shows the start page
- [ ] T022 [US3] End-to-end test: change the welcome text on a branch, merge to `main`, verify the new version appears live in ≤ 15 minutes with zero manual steps

**Checkpoint**: FR-006/FR-007/FR-014 proven live.

---

## Phase 6: Polish & Cross-Cutting

- [ ] T023 [P] Verify reboot resilience: `sudo reboot` the Pi; all pods healthy ≤ 5 min (SC-003)
- [ ] T024 [P] Secrets scan of both repos (no token/password committed) (SC-005)
- [ ] T025 [P] Finalize `README.md` + runbook sections (passwords, cert swap, webhook switch) and validate every command in `quickstart.md`
- [ ] T026 Remove the Sync Impact Report HTML comment from `.specify/memory/constitution.md` before the final commit

---

## Dependencies & Execution Order

1. Phase 1 (Setup) — first.
2. Phase 2 (US1) — cluster must exist before anything else.
3. Phase 3 (US4) — before US2, because Jenkins/ArgoCD ingresses use the TLS secret.
4. Phase 4 (US2) — Jenkins must exist before any pipeline run (US3).
5. Phase 5 (US3) — needs all previous phases.
6. Phase 6 — last.

Parallel: T002/T003 (docs) parallel with T004; T010/T011 parallel; T016–T018
parallel with T019–T020 (different repositories).

## Implementation Strategy

MVP = Phases 1–2 (working cluster). Each phase is validated at its checkpoint
before moving on. The full demo of value is T022.
