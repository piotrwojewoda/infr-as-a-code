# Feature Specification: Tests Before Deployment

**Feature Branch**: `002-tests-before-deploy`

**Created**: 2026-10-17

**Status**: Draft

**Input**: User description: "Projects deployed through the CI/CD platform must
have automated tests executed before deployment. The requirement applies to all
projects deployed through the platform. The gate runs the project's own
automated test suite only (no mandatory static analysis). A project without a
defined test suite must not be deployed."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Failing tests block a deployment (Priority: P1)

A developer merges a pull request into `main` of an application repository.
The pipeline starts, checks out the code and runs the application's automated
test suite. The tests fail. The pipeline stops immediately: no container image
is built or pushed, the GitOps repository is not touched, and the previously
deployed version keeps serving users without interruption.

**Why this priority**: This is the core value of the feature — broken code must
never reach production. Everything else is secondary to this guarantee.

**Independent Test**: Introduce a deliberately failing test in the demo
repository, merge it to `main`, wait for the pipeline, and verify that the
pipeline run is marked failed and the public URL still serves the old version.

**Acceptance Scenarios**:

1. **Given** a merged commit whose test suite fails, **When** the pipeline
   finishes, **Then** the run is marked as failed and the deployed application
   still serves the previous version.
2. **Given** a merged commit whose test suite passes, **When** the pipeline
   finishes, **Then** the new version is deployed exactly as before this
   feature existed.

---

### User Story 2 - A project without tests cannot be deployed (Priority: P2)

The operator onboards a new application to the platform (or removes the test
suite from an existing one). The application does not declare any automated
test suite. The pipeline stops before building an image and reports clearly
that a test suite is required for deployment. The application is not deployed.

**Why this priority**: The requirement applies to all projects on the platform.
Without this enforcement, a project could silently bypass the gate by simply
not defining tests.

**Independent Test**: Point the pipeline at a repository with no test suite
declaration, trigger a run, and verify it fails fast with a clear "tests
required" message and nothing is deployed.

**Acceptance Scenarios**:

1. **Given** an application repository with no declared test suite, **When**
   the pipeline runs, **Then** it fails before any image build with a message
   stating that a test suite is mandatory.
2. **Given** the same repository, **When** the developer adds a test suite
   declaration and merges again, **Then** the pipeline runs the tests and
   proceeds normally.

---

### User Story 3 - Developer understands and fixes a blocked release (Priority: P3)

A developer's merge is blocked by the test gate. The developer opens the
pipeline run, sees which tests failed and why, pushes a fix, and the next
pipeline run deploys the fixed version. No cluster access and no manual
deployment step is needed at any point.

**Why this priority**: A gate that blocks without clear feedback would push
developers to bypass it. Clear feedback keeps the gate accepted and effective.

**Independent Test**: Trigger a test failure, read the pipeline output, and
confirm it names the failing tests. Merge a fix and confirm the pipeline
recovers and deploys without manual intervention.

**Acceptance Scenarios**:

1. **Given** a pipeline run blocked by failing tests, **When** the developer
   opens the run output, **Then** the failing tests and their failure reason
   are identifiable without cluster access.
2. **Given** a previously failed run, **When** a fix is merged to `main`,
   **Then** a new pipeline run starts automatically and deploys the fixed
   version.
3. **Given** a pipeline run that is still in progress, **When** the developer
   opens the job in the Jenkins UI, **Then** the pipeline stages are shown as
   a sequence and the currently executing stage is visibly marked, without
   waiting for the run to finish.

---

### Edge Cases

- The test stage itself errors (e.g., test environment cannot start): the
  pipeline MUST treat it as a failure — no deployment. An inconclusive result
  is never a pass.
- A test suite hangs or runs extremely long: the pipeline MUST abort the run
  after a bounded time and treat it as a failure; the old version stays live.
- Two merges happen quickly after each other: each merge runs its own full
  gate; deployment order is preserved and the last green version wins.
- A flaky test fails intermittently: the pipeline stays re-runnable, but a
  failed run still blocks deployment — there is no "skip tests" override.
- An urgent hotfix is needed: it goes through the same gate as any other
  change. No manual bypass exists, because deploying untested code is exactly
  what this feature prevents.
- Tests need external services (e.g., a database): the project must provide
  ephemeral, CI-local equivalents; the gate never touches production data.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: Every application pipeline on the platform MUST execute the
  project's automated test suite after checkout and before any container image
  is built or pushed.
- **FR-002**: A failed or inconclusive test run MUST stop the pipeline: no
  image push, no GitOps repository update, no deployment.
- **FR-003**: When the test gate fails, the currently deployed version MUST
  remain running and untouched.
- **FR-004**: An application that does not declare an automated test suite
  MUST fail the pipeline fast (before any image build) with a clear message
  that tests are mandatory, and MUST NOT be deployed.
- **FR-005**: The pipeline MUST record the test outcome per run, including
  which tests failed and why, viewable without access to the cluster.
- **FR-006**: The gate MUST apply to every application deployed through the
  platform — existing and future ones alike.
- **FR-007**: After a failed run, the pipeline MUST be re-runnable (manually
  and by a new merge) so a fixed or flaky suite can recover.
- **FR-008**: The platform MUST define one documented, uniform way for a
  project to declare its test suite, so every project is gated the same way.
- **FR-009**: The test gate MUST NOT weaken existing pipeline guarantees:
  immutable image tags, GitOps commit as the only deployment trigger, and no
  direct cluster mutation from CI.
- **FR-010**: Every pipeline MUST appear in the Jenkins UI as a sequence of
  named stages, and the stage currently executing MUST be visibly
  distinguishable while the run is still in progress.

### Key Entities

- **Test gate**: the mandatory pipeline checkpoint that runs a project's test
  suite and blocks the release on failure.
- **Test suite declaration**: the project's own definition of which automated
  tests exist and how they are executed; owned by the project, required by the
  platform.
- **Release**: one deployed application version, identified by the git commit
  hash — a release exists only when its test gate passed.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: 100% of deployed versions have a passed test run attached to
  their pipeline run; a merge with failing tests never appears on the public
  URL.
- **SC-002**: A failing test suite causes zero downtime: the previous version
  keeps serving for the entire duration of the failed run.
- **SC-003**: A project without a test suite is rejected before any image
  build starts, i.e., within the first minutes of the pipeline run.
- **SC-004**: The merge-to-deploy time with the gate stays within the existing
  platform budget of 15 minutes for a typical project test suite.
- **SC-005**: For every blocked release, the failing tests are identifiable
  from the pipeline output alone, without cluster or server access.
- **SC-006**: During any in-progress pipeline run, the currently executing
  stage is identifiable in the Jenkins UI in under 3 clicks from the job
  page, without cluster or server access.

## Assumptions

- Each project owns its test suite and keeps it meaningful; the platform
  enforces execution, not test quality or coverage levels.
- The gate runs the project's automated tests only. Static analysis and
  linting stay optional per project (confirmed with the stakeholder).
- The pipeline must be observable in the Jenkins UI at stage level, live
  (confirmed with the stakeholder during planning).
- A missing test suite blocks deployment (confirmed with the stakeholder) —
  this is a deliberate policy, not an oversight.
- Tests run in the ephemeral CI environment, never against the production
  cluster or production data; projects provide their own ephemeral test
  dependencies.
- A typical project's test suite fits within the existing 15-minute
  merge-to-deploy budget; unusually heavy suites are the project's
  responsibility to optimize.
- Constitution principle V (Automated Delivery) describes the pipeline as
  "builds and pushes an image"; it will need a MINOR amendment to mention the
  test gate once this feature is implemented.
