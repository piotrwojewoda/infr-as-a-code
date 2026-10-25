# Tasks: Tests Before Deployment

**Input**: Design documents from `/specs/002-tests-before-deploy/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/
(pipeline.md, test-suite.md), quickstart.md

**Organization**: Tasks are grouped by user story. Execution order note: Phase 2
(shared library + Jenkins config) BLOCKS everything — the gate must exist on the
cluster before any story can be validated. US2 and US3 are live-validation
phases that reuse the pipeline built for US1. Doc amendments (constitution,
AGENTS.md, 001 contract) land in the Polish phase so they describe validated
reality.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: US1..US3 from spec.md

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: verify external facts flagged in research.md before building on them

- [x] T001 Verify multi-arch support: `docker manifest inspect php:8.5-cli` and `docker manifest inspect composer:2` both list `linux/arm64` (research.md D3; constitution constraint) — if either fails, pick the newest matching tag that does and record the choice in `specs/002-tests-before-deploy/research.md` — verified 2026-10-17 via Docker Hub registry API: both publish `linux/arm64` (and 6 other platforms)
- [x] T002 Create directory `jenkins/shared-library/vars/` in `infr-as-a-code` (library home; `libraryPath` keeps it out of the repo root — plan.md Structure Decision) — created with `vars/ciPipeline.groovy` (T003)

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: the enforced pipeline must exist on the cluster before ANY user
story can be implemented or validated

**⚠️ CRITICAL**: No user story work can begin until this phase is complete

- [x] T003 Write `jenkins/shared-library/vars/ciPipeline.groovy` implementing contracts/pipeline.md: `def call(Map config)` with required `config.app`, `config.testImage`, optional `config.testDeps` (`[image, command]`); pod template (jnlp + kaniko + git + the two test containers, ARM64 images, agent limits ≤ 1 CPU / 1 Gi); pipeline `options { timeout(time: 30, unit: 'MINUTES') }`; named stages exactly `Checkout` → `Test` → `Build & Push` → `Update GitOps`. Stage `Test`: wrapped in `timeout(time: 15, unit: 'MINUTES')`; fail fast with error message `ci/test.sh not found — an automated test suite is mandatory for deployment`; run `testDeps.command` in the deps container; run `./ci/test.sh` in `testImage`; fail with a clear message when `build/junit.xml` is missing afterwards; publish via `junit 'build/junit.xml'`. Stages `Build & Push` + `Update GitOps`: Kaniko build/push (`ghcr.io/piotrwojewoda/<app>:<short-sha>` + `:latest`, authenticated with the `ghcr-push` Secret since spec 004) and the GitOps `image.tag` bump; GitOps push uses `withCredentials` usernamePassword `github-pat` — done; two optional params added during implementation (`gitopsValues`, `registry`), contract updated accordingly
- [x] T004 [P] Update `clusters/malina/bootstrap/jenkins-values.yaml`: add `junit` and `pipeline-stage-view` to `controller.installPlugins`; add JCasC `unclassified.globalLibraries` entry — name `malina-ci`, `defaultVersion: main`, `implicit: true`, `allowVersionOverride: false`, retriever `modernSCM` git remote `https://github.com/piotrwojewoda/infr-as-a-code.git` with `libraryPath: jenkins/shared-library/`; refresh the Job DSL description to mention the mandatory test gate — done; YAML validity verified locally
- [ ] T005 Commit T002–T004 and push to `main` of `infr-as-a-code` (the library is fetched from GitHub `main` at run time); re-run `clusters/malina/bootstrap/10-install-platform.sh` to Helm-upgrade Jenkins; verify in the Jenkins UI: plugins `junit` + `pipeline-stage-view` installed, *Manage Jenkins → System* shows global library `malina-ci` (implicit, version `main`)

**Checkpoint**: Jenkins restarts with the new configuration; a replay of the
existing `demo-symfony-k3s` job still checks out code (old Jenkinsfile) without
errors.

---

## Phase 3: User Story 1 — Failing tests block a deployment (Priority: P1) 🎯 MVP

**Goal**: a merge whose tests fail never reaches production; the running version
stays untouched.

**Independent Test**: quickstart.md Scenario A (green path) + Scenario B
(failing test blocks, fix recovers).

- [x] T006 [US1] In repo `demo-symfony-k3s`: add `phpunit/phpunit` to `require-dev` in `composer.json` (version supporting PHP 8.5, e.g. `^12`) and commit the updated `composer.lock` — done via `symfony/test-pack` per the app repo's AGENTS.md (installed PHPUnit 13.4.3 + browser-kit; uncommitted, local PHP 8.4 needed `--ignore-platform-req=php`)
- [x] T007 [P] [US1] In repo `demo-symfony-k3s`: write `phpunit.xml` (testsuite dir `tests/`) and one smoke test `tests/SmokeTest.php` asserting the application boots (kernel boots / `GET /` returns 200) — done as Flex-recipe `phpunit.dist.xml` + `tests/Controller/HomeControllerTest.php` (3 tests: version table, DB-down page render, `/healthz`); verified green locally incl. `--log-junit build/junit.xml`
- [x] T008 [US1] In repo `demo-symfony-k3s`: write executable `ci/test.sh` per contracts/test-suite.md verbatim behavior — `#!/usr/bin/env bash`, `set -euo pipefail`, `mkdir -p build`, `vendor/bin/phpunit --log-junit build/junit.xml`; commit with the executable bit set — done and verified locally (exit 0, `build/junit.xml` produced, `/build/` git-ignored)
- [x] T009 [US1] In repo `demo-symfony-k3s`: replace `Jenkinsfile` with the one-liner from contracts/pipeline.md — `ciPipeline(app: 'demo-symfony-k3s', testImage: 'php:8.5-cli', testDeps: [image: 'composer:2', command: 'composer install --no-interaction --prefer-dist --no-progress'])` — done; file carries a warning comment: do not merge before the shared library lands (T003–T005)
- [ ] T010 [US1] Validate green path (quickstart.md Scenario A): merge a small visible change to `main`; run is `SUCCESS`; JUnit result attached to the run; stage diagram shows `Checkout → Test → Build & Push → Update GitOps`; new version live on `https://demo.kreciowo.pl` within 15 min (SC-004)
- [ ] T011 [US1] Validate blocking (quickstart.md Scenario B): merge a commit that makes the smoke test fail → run fails in stage `Test`, stage `Build & Push` never runs, `clusters/malina/values/demo-symfony.yaml` has no release commit for the broken SHA, old version serves without downtime (FR-002/FR-003, SC-001/SC-002); merge a revert → run green and deploys (FR-007)

**Checkpoint**: US1 fully functional — a red suite can no longer reach
production, a green one deploys exactly as before.

---

## Phase 4: User Story 2 — A project without tests cannot be deployed (Priority: P2)

**Goal**: a repository without a test-suite declaration is rejected fast, before
any image build, with a clear message.

**Independent Test**: quickstart.md Scenario C (fork without `ci/test.sh`).

- [ ] T012 [US2] Validate missing-suite rejection (quickstart.md Scenario C): fork `demo-symfony-k3s`, delete `ci/test.sh` in the fork, run a throwaway pipeline job `ciPipeline(app: 'demo-symfony-k3s-fork', testImage: 'php:8.5-cli')` against the fork → run fails inside stage `Test` before any build with the message `ci/test.sh not found — an automated test suite is mandatory for deployment` (FR-004, SC-003); delete the throwaway job and the fork afterwards

**Checkpoint**: the gate cannot be bypassed by simply not declaring tests.

---

## Phase 5: User Story 3 — Developer understands and fixes a blocked release (Priority: P3)

**Goal**: failure feedback and live progress are visible in the Jenkins UI
without cluster access.

**Independent Test**: quickstart.md Scenario B step 3 (reporting) and Scenario D
(timeout) + live stage observation during any run.

- [ ] T013 [P] [US3] Verify failure reporting: open the failed run from T011 → the `Test` stage is marked failed in the stage diagram and the JUnit view names the failing test with its failure output (FR-005, SC-005)
- [ ] T014 [P] [US3] Verify live visibility: during any in-progress run, open the job page → the stage diagram marks the currently executing stage within ≤ 3 clicks from the job page (FR-010, SC-006); the run's "Pipeline Steps" page lists individual steps
- [ ] T015 [US3] Validate timeout (quickstart.md Scenario D): on the fork, make `ci/test.sh` sleep beyond the stage timeout → the run is aborted at stage `Test` after 15 min, marked failed, nothing deployed; clean up the fork job

**Checkpoint**: a blocked release is self-explanatory from the Jenkins UI alone.

---

## Phase 6: Polish & Cross-Cutting

**Purpose**: make the written sources of truth match the validated reality

- [ ] T016 [P] Update `specs/001-k3s-cicd-platform/contracts/pipeline.md` to the v2 stage list (insert stage `Test`, new failure rows, enforcement note) so it matches `specs/002-tests-before-deploy/contracts/pipeline.md`
- [ ] T017 [P] Amend `.specify/memory/constitution.md` principle V: "Jenkins runs the application test suite, builds and pushes an image, …"; bump version 1.0.0 → 1.1.0 and set **Last Amended** to the commit date; commit message states the reason (governance rule)
- [ ] T018 [P] Add to `AGENTS.md` Non-negotiables: every deployment is gated by the project's automated test suite (`ci/test.sh`); failing or missing tests never deploy; there is no manual bypass
- [ ] T019 [P] Update `README.md`: extend the delivery-chain line to "merge → webhook → **tests** → build → push image → bump `image.tag` → ArgoCD rollout"
- [ ] T020 Final pass of `specs/002-tests-before-deploy/quickstart.md` Scenarios A–D end-to-end + secrets scan of all changed files in both repositories (constitution III)

---

## Dependencies & Execution Order

1. Phase 1 (Setup) — fact checks first; T001 may change chosen image tags.
2. Phase 2 (Foundational) — BLOCKS all stories: T003 ∥ T004, then T005 applies
   them to the cluster (the library must be on GitHub `main` before Jenkins
   can load it).
3. Phase 3 (US1) — needs Phase 2; T006–T009 are app-repo changes
   (T006 → T008; T007 ∥ T006; T009 independent), then validations T010 → T011.
4. Phase 4 (US2) — needs the gate live (Phase 2); independent of Phase 3 but
   cheaper after US1's pipeline is proven.
5. Phase 5 (US3) — reuses US1's runs (T011) plus its own validations.
6. Phase 6 — last; T016–T019 ∥, then T020.

### Parallel Opportunities

- T001 ∥ T002 (different concerns)
- T003 ∥ T004 (different files)
- T006 ∥ T007 (composer metadata vs test files — but T008 needs T006's `vendor/bin/phpunit`)
- T013 ∥ T014 (two independent UI verifications)
- T016 ∥ T017 ∥ T018 ∥ T019 (four different files)

## Implementation Strategy

MVP = Phases 1–3 (US1): the gate blocks red code from production — the core
value. US2 and US3 are mostly validation of behaviors the design already
delivers, so each phase ends with a live, independently checkable checkpoint.
Full value demo = T011 (broken merge provably never reaches
`https://demo.kreciowo.pl`).
