# Quickstart: Validating the Test Gate

**Feature**: 002-tests-before-deploy | **Date**: 2026-10-17

Runnable scenarios that prove the test gate works end to end. Prerequisite:
the malina platform is installed (feature 001) and reachable at
`https://kreciowo.pl/jenkins/`.

## 0. Rollout (one time)

1. Merge the platform changes of this feature to `main` of
   `infr-as-a-code` (shared library under `jenkins/shared-library/`,
   updated `jenkins-values.yaml`, contract updates).
2. Re-run the documented Jenkins install/upgrade path:
   `clusters/malina/bootstrap/10-install-platform.sh` (Helm upgrade of
   Jenkins with the new values).
3. Verify in the Jenkins UI: *Manage Jenkins → Plugins* lists `junit` and
   `pipeline-stage-view`; *Manage Jenkins → System* shows the global library
   `malina-ci` (implicit, version `main`).
4. Merge the `demo-symfony-k3s` changes (new `ci/test.sh`, PHPUnit smoke
   test, one-line `Jenkinsfile`).

## Scenario A — green path (normal release still works)

1. Merge a small visible change to `main` of `demo-symfony-k3s`.
2. **While the pipeline runs**, open the job in Jenkins: the stage diagram
   shows `Checkout → Test → Build & Push → Update GitOps` and the currently
   executing stage is marked live. (Validates FR-010 / SC-006.)
3. When the run finishes: it is `SUCCESS`; the run page shows the JUnit
   result of the `Test` stage; `https://demo.kreciowo.pl` serves the new
   version. (Validates FR-001, FR-005, US1 scenario 2.)

## Scenario B — failing tests block the deployment

1. Create a commit that makes the smoke test fail; merge it to `main`.
2. The pipeline fails in stage `Test`. **No** `Build & Push` stage runs.
3. Open the failed run: the JUnit view names the failing test and its
   failure output — no cluster access needed. (FR-005, SC-005.)
4. `https://demo.kreciowo.pl` still serves the previous version, without
   any downtime. (FR-002, FR-003, SC-001, SC-002.)
5. `clusters/malina/values/demo-symfony.yaml` in git has **no** new release
   commit for the broken SHA.
6. Merge a revert/fix: the next run goes green and deploys. (FR-007,
   US3 scenario 2.)

## Scenario C — missing test suite is rejected (on a fork)

1. Fork `demo-symfony-k3s`, delete `ci/test.sh` in the fork.
2. Temporarily point the seeded Jenkins job at the fork (job configuration
   page → source URL), or add a throwaway pipeline job with
   `ciPipeline(app: 'demo-symfony-k3s-fork', testImage: 'php:8.5-cli')`.
3. Run it: the run fails **in stage `Test`, before any build**, with the
   message `ci/test.sh not found — an automated test suite is mandatory for
   deployment`. (FR-004, SC-003.)
4. Revert the job to the real repository and delete the throwaway job/fork.

## Scenario D — timeout and inconclusive runs

1. On the fork, make `ci/test.sh` sleep longer than the stage timeout.
2. The run is aborted at the `Test` stage after 15 minutes and marked
   failed; nothing is deployed. (Edge case: hung suite; D5.)
3. Delete the fork job afterwards.

## Rollback

If the gate misbehaves: revert the `jenkins-values.yaml` change, re-run
`10-install-platform.sh`, and restore the previous `Jenkinsfile` in the app
repository. The last deployed application version is never affected by any
of the scenarios above.

> Note: scenarios B–D deliberately break `main` or use a fork. Keep them
> short and revert immediately; the platform's own guarantees (old version
> keeps serving) are exactly what is being validated.
