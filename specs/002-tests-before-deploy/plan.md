# Implementation Plan: Tests Before Deployment

**Branch**: `002-tests-before-deploy` | **Date**: 2026-10-17 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/002-tests-before-deploy/spec.md`

## Summary

Add a mandatory test gate to the delivery pipeline of the malina platform.
The gate is enforced by a **global Jenkins shared pipeline library** that lives
in this GitOps repository (`jenkins/shared-library/`) and is loaded implicitly
for every pipeline job (no per-project opt-out). The library defines the stage
order `Checkout → Test → Build & Push → Update GitOps`; the existing Kaniko
build and GitOps tag bump move unchanged into the library. Each application
repository declares its test suite as an executable `ci/test.sh` that must
produce a JUnit report; a missing or failing suite stops the pipeline before
any image is built and leaves the deployed version untouched. The pipeline
appears in the Jenkins UI as named stages with the currently executing one
marked live (Pipeline Stage View plugin). The demo application
(`demo-symfony-k3s`) is onboarded first: it gains a PHPUnit smoke suite, a
`ci/test.sh`, and a one-line Jenkinsfile calling the shared library.

## Technical Context

**Language/Version**: Groovy (Jenkins shared library, CPS), Bash 5
(`ci/test.sh` contract), YAML (JCasC / Helm values), PHP 8.5 + PHPUnit ^12
(demo application's own suite)

**Primary Dependencies**: Jenkins kubernetes plugin (existing), Pipeline:
Groovy Libraries `pipeline-groovy-lib` (already bundled with
`workflow-aggregator`), `junit` plugin (new), `pipeline-stage-view` plugin
(new), container images `php:8.5-cli` and `composer:2` (both publish
`linux/arm64` manifests — to be re-verified during implementation)

**Storage**: N/A for the feature itself (agent workspace is an ephemeral pod
volume; JUnit results are archived in the existing Jenkins home PVC)

**Testing**: live validation runs on the cluster per `quickstart.md` — green
path, failing-test path, missing-suite path (on a fork)

**Target Platform**: existing k3s cluster `malina` (Raspberry Pi 5, ARM64,
8 GB RAM), Jenkins LTS installed from the jenkinsci Helm chart

**Project Type**: CI/CD platform configuration (GitOps)

**Performance Goals**: typical suite + full pipeline within the existing
15-minute merge-to-deploy budget; hard pipeline timeout 30 min, test stage
timeout 15 min

**Constraints**: all images `linux/arm64`; test containers must fit the
existing agent limits (≤ 1 CPU / 1 Gi); no secrets in git (library references
credential IDs only); no direct cluster mutation from CI

**Scale/Scope**: 1 shared-library entry point (`ciPipeline`), 2 contract
documents, 1 application onboarded (`demo-symfony-k3s`), amendments to
`jenkins-values.yaml`, the 001 pipeline contract, the constitution and
AGENTS.md

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Verdict | Evidence / Justification |
|-----------|---------|--------------------------|
| I. GitOps First | PASS | The shared library, the JCasC change and the contract live in this repository; Jenkins loads the library from `main` of this same repository on GitHub, so git remains the single source of truth. No manual `kubectl`/`helm` change is introduced — the Jenkins chart upgrade goes through the documented bootstrap path. |
| II. Infrastructure as Code | PASS | New behaviour is code: `vars/ciPipeline.groovy`, JCasC `globalLibraries`, plugin list. |
| III. No Secrets in Git | PASS | The library references the existing credential ID `github-pat` only; the PAT stays in the bootstrap-created Kubernetes Secret. Test runs need no secrets at all. |
| IV. Simplicity First | PASS | Two additional Jenkins plugins and one Groovy file; no new runtime component, no new namespace, no new Helm release. The shared library is the minimal Jenkins mechanism that enforces a stage for *every* project. |
| V. Automated Delivery | PASS (amended) | The single delivery path gains a mandatory Test stage. Constitution principle V text ("builds and pushes an image") will be amended to "runs the test suite, builds and pushes an image" with a MINOR version bump (1.0.0 → 1.1.0) as part of implementation. |

Post-design re-check: passed (see research.md decisions D1–D7).

## Project Structure

### Documentation (this feature)

```text
specs/002-tests-before-deploy/
├── plan.md              # This file
├── research.md          # Phase 0: decisions D1–D7
├── data-model.md        # Phase 1: gate/declaration/run entities
├── quickstart.md        # Phase 1: validation runbook (green / failing / missing suite)
├── contracts/           # Phase 1: interfaces
│   ├── pipeline.md      # CI pipeline contract v2 (supersedes stage list of 001)
│   └── test-suite.md    # ci/test.sh declaration contract for app repositories
└── tasks.md             # Phase 2 output (/speckit.tasks - NOT created by /speckit.plan)
```

### Source Code (repository root = `infr-as-a-code`)

```text
.
├── jenkins/
│   └── shared-library/
│       └── vars/
│           └── ciPipeline.groovy      # global shared pipeline, loaded implicitly
├── clusters/malina/bootstrap/
│   └── jenkins-values.yaml            # + junit & pipeline-stage-view plugins,
│                                      # + JCasC globalLibraries (libraryPath), job description
├── specs/001-k3s-cicd-platform/contracts/pipeline.md  # stage list updated to v2
├── .specify/memory/constitution.md    # principle V amendment, version 1.1.0
└── AGENTS.md                          # non-negotiables: + test gate rule
```

The application repository `demo-symfony-k3s` (separate, out of this repo's
scope but part of the feature) gains: `ci/test.sh`, `phpunit.xml`,
`composer.json` require-dev `phpunit/phpunit`, one smoke test, and a one-line
Jenkinsfile calling `ciPipeline(...)`.

**Structure Decision**: the platform side is small and fits the existing
layout — one new top-level directory `jenkins/shared-library/` (a Jenkins
shared library needs `vars/`; `libraryPath` in the JCasC retriever keeps it
out of the repository root). Everything else is edits to existing files.

## Complexity Tracking

No constitution violations → no justifications required.

## Phase Outputs

- Phase 0 → [research.md](./research.md) — decisions D1–D7 with alternatives.
- Phase 1 → [data-model.md](./data-model.md), [contracts/](./contracts),
  [quickstart.md](./quickstart.md).
- Phase 2 → tasks.md (created by `/speckit.tasks`).
