# Phase 0 Research: Test Gate Decisions

**Feature**: 002-tests-before-deploy | **Date**: 2026-10-17

Every decision below was checked against the constitution. No external
environment changes were needed for this research; the facts about the cluster
come from the live platform installed by feature 001.

## D1 — Enforcement point: global shared pipeline library

- **Decision**: Put the pipeline in a Jenkins *global shared library* stored in
  this repository at `jenkins/shared-library/vars/ciPipeline.groovy`. JCasC
  registers it as a global library (`globalLibraries`) with `implicit: true`
  and `allowVersionOverride: false`, fetched from `main` of
  `piotrwojewoda/infr-as-a-code` with `libraryPath: jenkins/shared-library/`.
  Every application Jenkinsfile becomes a one-liner: `ciPipeline(app:
  'demo-symfony-k3s', testImage: 'php:8.5-cli', testDeps: [image:
  'composer:2', command: 'composer install ...'], gitopsValues:
  'clusters/malina/values/demo-symfony.yaml')` (optional parameters added
  during implementation: `gitopsValues`, `registry` — see contracts/pipeline.md).
- **Alternatives**:
  - *Keep the Jenkinsfile per app repo and document the Test stage as a
    convention* — a project could edit its own Jenkinsfile and silently remove
    the gate. Violates FR-006 (gate must apply to every application).
  - *Move the whole Jenkinsfile into this repo (platform-owned scriptPath)* —
    the job would check out this repo first and the app repo second; bigger
    change to the working 001 setup and mixes two checkouts in one job.
- **Why**: the shared library is the standard Jenkins mechanism for
  organisation-wide pipeline policy. The stage order is fixed in one file in
  the GitOps repo (code review protects it), while per-app variation is
  reduced to declared parameters. Implicit loading + no version override means
  an app cannot bypass or pin around the gate.

## D2 — Test suite declaration: `ci/test.sh` contract

- **Decision**: An application declares its test suite as an executable file
  `ci/test.sh` at the repository root. Exit code 0 = pass, non-zero = fail;
  the script MUST write a JUnit XML report to `build/junit.xml`. Details in
  [contracts/test-suite.md](./contracts/test-suite.md).
- **Alternatives**:
  - *Auto-detection* (`composer test`, `npm test`, `make test` …) — magic,
    different per stack, hard to debug; violates KISS.
  - *Test commands inline in the app Jenkinsfile* — no uniform contract, and
    conflicts with D1 (the Jenkinsfile becomes a one-liner).
- **Why**: one explicit, stack-agnostic file is the simplest possible uniform
  interface (FR-008). Existence is trivially checkable, which gives the
  fail-fast behaviour for missing suites (FR-004).

## D3 — Test execution environment: containers in the agent pod

- **Decision**: Tests run in the existing Kubernetes agent pod, in a container
  started from the declared `testImage` (`php:8.5-cli` for the demo app). An
  optional dependency step runs first in a second container (`composer:2`
  runs `composer install`), sharing the pod workspace so `vendor/` is
  available to the test container.
- **Alternatives**:
  - *Run tests inside the Kaniko image build (multi-stage Dockerfile)* —
    couples tests to the image build, gives no JUnit report to Jenkins, and a
    build could skip the test stage with a build argument; the image is also
    built before anyone knows the tests pass.
  - *One fat image containing PHP + Composer* — no official image; maintaining
    a custom test image contradicts KISS.
- **Why**: standard Jenkins-on-Kubernetes practice, reuses the existing agent
  machinery, produces archivable reports, and fails *before* any image build
  (SC-003). Both `php` and `composer` official images publish `linux/arm64`
  manifests (constitution constraint; re-verify at implementation time).

## D4 — Reporting: JUnit via the `junit` plugin

- **Decision**: Add the `junit` plugin to `jenkins-values.yaml` (it is NOT
  bundled with `workflow-aggregator`). After `ci/test.sh` exits 0, the library
  checks `build/junit.xml` exists (missing report = failed run, clear
  message) and publishes it with the `junit` step, so every run records
  pass/fail counts and failure details viewable in the Jenkins UI (FR-005),
  no cluster access needed.
- **Alternatives**: parse console output only (fragile, no trend); archive the
  raw log as a build artifact (meets the letter of FR-005 but poor
  readability).
- **Why**: JUnit is the Jenkins-native, tool-agnostic test report format; the
  contract already requires the suite to emit it.

## D5 — Timeouts and inconclusive results

- **Decision**: Pipeline-level `timeout(30)` minutes; the Test stage is
  wrapped in `timeout(15)`. An aborted/errored/timed-out stage is a failure:
  the run stops and the deployed version is untouched. Re-running is always
  possible (Jenkins *Rebuild* or a new merge), satisfying FR-007.
- **Alternatives**: no timeout (a hung suite blocks the executor and delays
  later merges); retry-on-failure inside the stage (masks flaky tests, the
  opposite of the spec's edge-case ruling).
- **Why**: bounded runs keep the 15-minute merge-to-deploy budget meaningful
  and make "inconclusive = failure" enforceable.

## D6 — Constitution and contract amendments

- **Decision**: Amend constitution principle V to name the test gate
  ("a merge to `main` … triggers Jenkins, Jenkins runs the application test
  suite, builds and pushes an image, …") and bump the constitution to 1.1.0
  (MINOR — new requirement in an existing principle). Update
  `specs/001-k3s-cicd-platform/contracts/pipeline.md` to the v2 stage list so
  the living contract matches reality. Add one line to `AGENTS.md`
  non-negotiables.
- **Alternatives**: leave the constitution as-is (the pipeline would then
  diverge from its own constitution); a MAJOR bump (the principle is extended,
  not redefined — MINOR is correct per the governance rules).
- **Why**: the constitution is binding and must describe the real pipeline.

## D7 — Live pipeline visualisation: Pipeline Stage View plugin

- **Decision**: Add the `pipeline-stage-view` plugin to
  `jenkins-values.yaml`. It draws the stage diagram on the job/run page and
  marks the stage that is executing right now (FR-010). The shared library
  MUST wrap work in named `stage(...)` blocks (`Checkout`, `Test`,
  `Build & Push`, `Update GitOps`) so the diagram is meaningful. Step-level
  detail (each `sh`, `container`, etc.) comes from the "Pipeline Steps" page
  already provided by the bundled `workflow-support` plugin — no extra
  install.
- **Alternatives**:
  - *Blue Ocean* — modern live UI, but a heavy plugin suite in maintenance
    mode; too much for an 8 GB Pi (Constitution IV, KISS).
  - *Console log only* — requires reading a scrolling log to find the current
    position; does not satisfy FR-010 ("visibly distinguishable").
- **Why**: `pipeline-stage-view` is the lightweight, classic-UI stage diagram.
  It was REMOVED from `workflow-aggregator` (JENKINS-41558), so it must be
  listed explicitly in `installPlugins`.

## Plugin bundling facts (verified 2026-10-17, plugins.jenkins.io + aggregator release notes)

- `workflow-aggregator` (608.v67378e9d3db_1) bundles: Pipeline: Groovy,
  Job, Multibranch, Basic Steps, Nodes and Processes, Stage Step,
  Declarative, Build Step, Input Step, Milestone Step and **Pipeline: Groovy
  Libraries** (`pipeline-groovy-lib`, the modern name of
  `workflow-cps-global-lib`).
- Consequence 1: global shared libraries (D1) need NO extra plugin.
- Consequence 2: `pipeline-stage-view` is NOT bundled → must be added (D7).
- Consequence 3: `junit` is NOT bundled → must be added (D4).

## Verified facts used above

| Fact | Source | Result |
|------|--------|--------|
| Jenkins runs on the cluster with JCasC + Job DSL from `jenkins-values.yaml` | 001 implementation | confirmed |
| Builds run on Kubernetes agents; controller has 0 executors | `jenkins-values.yaml` | confirmed |
| GitHub PAT available as Jenkins credential `github-pat` | JCasC in `jenkins-values.yaml` | confirmed |
| Registry is GitHub Container Registry (spec 004, private, authenticated) | 004 research / contracts/registry.md | current |
| `php:8.5-cli` official image is multi-arch incl. arm64 | Docker Hub registry API manifest list | confirmed 2026-10-17 (386/amd64/arm/arm64/ppc64le/riscv64/s390x) |
| `composer:2` official image is multi-arch incl. arm64 | Docker Hub registry API manifest list | confirmed 2026-10-17 (same platform set) |
