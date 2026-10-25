# Tasks: Move Image Hosting to GitHub Container Registry

**Input**: Design documents from `/specs/004-ghcr-image-hosting/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md,
contracts/registry.md, quickstart.md

**Organization**: implementation tasks first, then live migration and
validation. Code changes all land in one commit; the live cleanup happens
once on the running cluster.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: US1..US3 from spec.md

---

## Phase 1: Setup

- [x] T001 Create feature docs under `specs/004-ghcr-image-hosting/` (spec, plan, research, data model, contract, quickstart)

---

## Phase 2: User Story 1 — CI pushes to GHCR (Priority: P1) 🎯 MVP

**Goal**: Jenkins/Kaniko publishes to `ghcr.io/piotrwojewoda/<app>` with the
`ghcr-push` Secret, no `--insecure`, no fallback.

**Independent Test**: one pipeline run creates a GHCR package version.

- [x] T002 [US1] Edit `jenkins/shared-library/vars/ciPipeline.groovy`: default `registry` → `ghcr.io/piotrwojewoda`; add pod volume from Secret `ghcr-push` (`key: .dockerconfigjson`, `path: config.json`) mounted at `/kaniko/.docker`; remove `--insecure`; update the header comment
- [x] T003 [P] [US1] Keep `10-install-platform.sh` creating `ghcr-push`/`ghcr-pull` from `GITHUB_TOKEN` and document the required `write:packages` scope in the header. Factor the two Secrets into `ghcr-secrets.sh` so the token can be rotated without re-running every other bootstrap secret

---

## Phase 3: User Story 2 — Pi pulls from GHCR (Priority: P1)

**Goal**: the demo Deployment references GHCR and uses `ghcr-pull`.

**Independent Test**: demo Pod is Running and its image is on `ghcr.io`.

- [x] T004 [US2] Edit `clusters/malina/values/demo-symfony.yaml`: `image.repository: ghcr.io/piotrwojewoda/demo-symfony-k3s`, `imagePullSecrets: [{ name: ghcr-pull }]`, update comments
- [x] T005 [P] [US2] Verify/update `charts/demo-symfony/values.yaml` defaults (GHCR repo, `ghcr-pull`); bump `charts/demo-symfony/Chart.yaml` version to 0.2.0

---

## Phase 4: User Story 3 — In-cluster registry removed (Priority: P2)

**Goal**: no registry workload, PVC, NodePort, mirror or firewall rule.

**Independent Test**: `kubectl -n registry get all` empty on live; fresh
bootstrap creates nothing.

- [x] T006 [US3] Delete `clusters/malina/infrastructure/registry.yaml`
- [x] T007 [US3] Edit `clusters/malina/bootstrap/10-install-platform.sh`: remove the registry apply and the `/etc/rancher/k3s/registries.yaml` mirror block (and the k3s restart it needed)
- [x] T008 [P] [US3] Edit `clusters/malina/bootstrap/05-hardening.sh`: remove the ufw rule for `30500/tcp`
- [x] T009 [P] [US3] Edit `clusters/malina/bootstrap/README.md`: GHCR-only description, token scope, no registry in the bootstrap order

---

## Phase 5: Documentation alignment

- [x] T010 [P] Update `README.md`: GHCR as the only registry, remove NodePort 30500 and the "GHCR fallback" wording
- [x] T011 [P] Update current-state notes in spec 001 (`research.md` D2, `quickstart.md`, `data-model.md`, `contracts/pipeline.md`) and spec 003 (`contracts/exposure.md`, `contracts/host-hardening.md`, relevant spec/data-model lines): mark the in-cluster registry superseded by feature 004 and remove 30500 from the exposure matrix
- [x] T012 Run repository checks: `helm template charts/demo-symfony --values clusters/malina/values/demo-symfony.yaml | kubectl apply --dry-run=client -f -`; `kubectl apply --dry-run=client -f clusters/malina/apps/`; `grep -rn "30500\|--insecure\|192.168.68.52:30500"` to confirm no live references remain

---

## Phase 6: Live migration (operator, one time)

- [ ] T013 Run `GITHUB_USER=... GITHUB_TOKEN=... bash ghcr-secrets.sh` with a PAT that has `write:packages` (updates the GHCR Secrets without touching other credentials)
- [ ] T014 Trigger one `demo-symfony-k3s` build; confirm GHCR package with SHA + `latest`; confirm demo Pod pulls from `ghcr.io`
- [ ] T015 Run quickstart step 3: delete the old registry namespace/PVC, the containerd mirror and the ufw 30500 rule
- [ ] T016 Run quickstart step 4 validation table (port closed, firewall clean, app 200, pipeline green)

---

## Dependencies & Execution Order

1. Phase 2 (US1) and Phase 3 (US2) are independent files and land together.
2. Phase 4 (US3) removes the old path; T006–T008 touch different files.
3. Phase 5 docs after code (T010–T011).
4. T012 is the static gate before committing.
5. Phase 6 only after the commit is merged and Jenkins has the new library.

### Parallel Opportunities

- T002 ∥ T003; T004 ∥ T005; T006 ∥ T007 ∥ T008 ∥ T009;
  T010 ∥ T011.

## Implementation Strategy

MVP = Phases 2–3: releases publish to and pull from GHCR. Phase 4 cleans up
the old component in the same commit. Phase 6 is the live acceptance gate;
the feature is "done" when the package exists and the registry namespace and
port are gone.
