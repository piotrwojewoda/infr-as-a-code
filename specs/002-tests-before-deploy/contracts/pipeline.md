# Contract: CI Pipeline v2 (Jenkins)

**Feature**: 002-tests-before-deploy | **Date**: 2026-10-17
**Supersedes**: the stage list in `specs/001-k3s-cicd-platform/contracts/pipeline.md`
(001's file is updated to match during implementation).

## Trigger

Unchanged: push/merge to `main` of the application repository → GitHub webhook
to `https://kreciowo.pl/jenkins/github-webhook/` (`githubPush()` trigger).

## Enforcement mechanism

- The pipeline body lives in the **global shared library** `malina-ci`
  (`jenkins/shared-library/vars/ciPipeline.groovy` in this repository),
  registered by JCasC with `implicit: true` and
  `allowVersionOverride: false`. No application can skip, reorder or pin
  around the stages.
- The application repository keeps a one-line `Jenkinsfile` that only passes
  parameters:

  ```groovy
  ciPipeline(
    app: 'demo-symfony-k3s',
    testImage: 'php:8.5-cli',
    testDeps: [image: 'composer:2', command: 'composer install --no-interaction --prefer-dist --no-progress'],
    gitopsValues: 'clusters/malina/values/demo-symfony.yaml'
  )
  ```

### `ciPipeline` parameters

| Parameter | Required | Meaning |
|-----------|----------|---------|
| `app` | yes | application name; used for the image name and release commit messages |
| `testImage` | yes | container image the test suite runs in; MUST support `linux/arm64` |
| `testDeps` | no | `[image, command]` — dependency-install step run in the same pod workspace before the tests |
| `gitopsValues` | no | values file bumped per release; default `clusters/malina/values/<app>.yaml` (the demo app passes `clusters/malina/values/demo-symfony.yaml`) |
| `registry` | no | image registry prefix; default `192.168.68.52:30500` (in-cluster). Change for the documented GHCR swap (research 001 D2) |

## Stages (fixed order, all named)

1. **Checkout** — full clone of the app repo at the merged commit.
2. **Test** *(new, mandatory)* —
   1. fail fast if `ci/test.sh` is missing: error message
      `ci/test.sh not found — an automated test suite is mandatory for deployment`;
   2. if `testDeps` is declared, run its `command` in the `testDeps.image`
      container (shared pod workspace);
   3. run `ci/test.sh` in the `testImage` container; non-zero exit = failed;
   4. fail if `build/junit.xml` is missing afterwards (clear message);
   5. publish the report with the `junit` step.
   The whole stage is wrapped in `timeout(15)`.
3. **Build & Push** — unchanged: Kaniko builds the app repo `Dockerfile` and
   pushes `192.168.68.52:30500/<app>:<short-sha>` (+ `:latest`) with
   `--insecure`.
4. **Update GitOps repo** — unchanged: set `image.tag: <short-sha>` in
   `clusters/malina/values/<app>.yaml`, commit
   `chore(release): <app> <short-sha>`, push to `main` (credential
   `github-pat`).
5. **Deploy** — unchanged: no direct action; ArgoCD syncs the GitOps change.

## Visualisation

- The four stages above MUST appear in the Jenkins UI (Pipeline Stage View)
  with these exact names; the currently executing stage is marked live.
- Stage bodies MUST use named `stage(...)` blocks; individual steps are
  visible on the "Pipeline Steps" page of the run.

## Guarantees

- A failed, missing, inconclusive or timed-out test suite stops the pipeline
  before any image is built; the running deployment is untouched.
- No bypass: the stage order is defined once in the shared library inside the
  GitOps repository; application Jenkinsfiles cannot change it.
- Every pushed image tag is immutable (`<short-sha>`); rollbacks stay
  "change the tag back" commits.
- The GitOps commit is still the only deployment trigger — no `kubectl` from
  Jenkins.
- Pipeline-level timeout: 30 minutes. An aborted run is a failed run.
- A failed run is always re-runnable (Jenkins *Rebuild* or a new merge).

## Inputs (unchanged)

Kubernetes Secret `jenkins-github` (namespace `jenkins`) → JCasC credential
`github-pat` (`GITHUB_USER` / `GITHUB_TOKEN`), used ONLY for the GitOps push.

## Failure handling

| Failure | Result |
|---------|--------|
| `ci/test.sh` missing | Fail fast in stage `Test`, no build, clear "tests mandatory" message |
| `testDeps` step fails | Run failed in stage `Test`, no build |
| Tests fail (exit ≠ 0) | Run failed, JUnit archived, old version keeps serving |
| `build/junit.xml` missing after green tests | Run failed, clear "report missing" message |
| Test stage exceeds 15 min | Stage aborted ⇒ run failed, old version keeps serving |
| Build fails | No image pushed, no GitOps commit, old version keeps running |
| Push fails | Same as above |
| GitOps push fails | Image exists but is not deployed; next successful run recovers |
