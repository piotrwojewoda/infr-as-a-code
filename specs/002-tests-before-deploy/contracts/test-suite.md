# Contract: Test Suite Declaration (`ci/test.sh`)

**Feature**: 002-tests-before-deploy | **Date**: 2026-10-17

This contract is the single, uniform way an application deployed through the
malina platform declares its automated test suite (FR-008). It is binding for
every application repository, existing and future.

## What the application repository MUST provide

1. **File**: `ci/test.sh` at the repository root, executable
   (`chmod +x`, the executable bit is committed to git).
2. **Behaviour**: running the script executes the application's automated
   test suite to completion.
3. **Exit code**: `0` = all tests passed; any non-zero code = failure.
4. **Report**: after a passing run, a JUnit XML report MUST exist at
   `build/junit.xml` (relative to the repository root). A missing report
   fails the pipeline even when the exit code is 0.

   > Terminology: "JUnit" here is only the name of the XML report format.
   > For PHP applications the tests are always executed by **PHPUnit**, which
   > produces this format natively (`phpunit --log-junit`). No Java tooling
   > is involved; the Jenkins `junit` plugin only renders the XML.

## Rules

- The script runs inside the container image declared as `testImage` in the
  application's `ciPipeline(...)` call, with the repository checked out as
  the working directory.
- Dependencies (e.g. `composer install`) are either installed by the
  declared `testDeps` step or by the script itself. The script MAY download
  packages from the network; it MUST NOT require access to the cluster, to
  production services or to any secret.
- Tests MUST be self-contained: any external service they need (database,
  cache) is an ephemeral, CI-local equivalent started by the script or by
  the test framework itself.
- The suite SHOULD finish well within 15 minutes (hard stage timeout). A
  longer suite is the project's responsibility to split or speed up.
- The suite MUST NOT be made optional by any parameter, environment
  variable or flag in the application repository.

## Minimal example (Symfony/PHP, as used by `demo-symfony-k3s`)

```bash
#!/usr/bin/env bash
set -euo pipefail
mkdir -p build
vendor/bin/phpunit --log-junit build/junit.xml
```

(with `testDeps: [image: 'composer:2', command: 'composer install
--no-interaction --prefer-dist --no-progress']` providing `vendor/`).

## How the platform consumes it

See [pipeline.md](./pipeline.md), stage **Test**: existence check → optional
deps step → run → report check → publish. Any violation of this contract
fails the pipeline before an image is built, and the previously deployed
version keeps running.
