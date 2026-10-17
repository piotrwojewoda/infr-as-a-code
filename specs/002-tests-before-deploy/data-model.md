# Phase 1 Data Model: Test Gate Entities

**Feature**: 002-tests-before-deploy | **Date**: 2026-10-17

This feature adds no persistent database. The entities below are
configuration and runtime concepts and the validation rules the pipeline
applies to them.

## TestSuiteDeclaration

Owned by the application repository; consumed by the test gate.

| Field | Rule | Source |
|-------|------|--------|
| `path` | fixed: `ci/test.sh` at the repository root | contract test-suite.md |
| `executable` | file MUST exist and be runnable; missing file ⇒ pipeline fails fast with "test suite is mandatory" | FR-004 |
| `exitCode` | `0` = tests passed; non-zero = tests failed | contract test-suite.md |
| `reportPath` | fixed: `build/junit.xml`; MUST exist after a passing run, else the run fails | FR-004, FR-005 |
| `testImage` | declared by the app in its `ciPipeline(...)` call; MUST support `linux/arm64` | contract pipeline.md |
| `testDeps` | optional `[image, command]` step run before tests (e.g. dependency install) | contract pipeline.md |

## TestGate

The mandatory checkpoint inside every application pipeline.

| Field | Rule |
|-------|------|
| position | after `Checkout`, before `Build & Push` — never reordered |
| inputs | checked-out workspace + TestSuiteDeclaration |
| outcomes | `passed` → pipeline continues; `failed` / `inconclusive` → pipeline stops |
| timeBudget | stage timeout 15 min; pipeline timeout 30 min; exceeded ⇒ `inconclusive` ⇒ stop |
| visibility | runs as a named stage `Test`, visibly marked while executing |
| bypass | none — defined in the global shared library, `allowVersionOverride: false` |

## PipelineRun

One execution of an application pipeline.

| Field | Rule |
|-------|------|
| `commit` | short SHA of the merged commit; becomes the image tag |
| `stages` | ordered list: `Checkout → Test → Build & Push → Update GitOps`; current stage observable live in the UI |
| `gateOutcome` | `passed` / `failed` / `inconclusive` — recorded per run |
| `testTotals` | tests run / failed / skipped, from the JUnit report; archived with the run |
| `result` | `SUCCESS` / `FAILURE` / `ABORTED` (aborted is never a pass) |

### State transitions

```text
queued → testing ──pass──→ building → releasing → deployed
            │
            ├──fail────────→ blocked (old release keeps running)
            ├──inconclusive→ blocked (old release keeps running)
            └──no declaration→ blocked (fail fast, before any build)
```

A `blocked` run never creates a Release. A new merge or a manual *Rebuild*
starts a new PipelineRun (FR-007).

## Release

Unchanged from feature 001 (image tag = short SHA, GitOps commit is the only
trigger) with one added precondition:

| Field | Rule |
|-------|------|
| `gatePrecondition` | a Release may be created only by a PipelineRun whose `gateOutcome` is `passed` |

## Relationships

```text
Application 1──1 TestSuiteDeclaration (required, missing ⇒ blocked)
Application 1──* PipelineRun
PipelineRun 1──1 TestGate (executes exactly once per run)
PipelineRun 0──1 Release (exists only when the gate passed)
```
