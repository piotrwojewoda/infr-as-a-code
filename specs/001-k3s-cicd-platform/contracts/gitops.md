# Contract: GitOps Layout (ArgoCD)

**Feature**: 001-k3s-cicd-platform | **Date**: 2026-10-17

## Repository layout that ArgoCD depends on

```text
infr-as-a-code (branch: main)
└── clusters/malina/
    ├── apps/root-app.yaml        # app-of-apps, path: clusters/malina/apps
    ├── apps/demo-postgres.yaml   # Bitnami postgresql, pinned chart version
    ├── apps/demo-symfony.yaml    # multi-source app (chart + $values)
    └── values/demo-symfony.yaml  # environment values (Jenkins bumps image.tag)
```

## root-app

- Watches `clusters/malina/apps` (directory recursion not needed).
- Sync policy: automated, `prune: true`, `selfHeal: true`.
- Anything deleted from git is removed from the cluster; manual cluster edits
  are reverted.

## demo-postgres

- Source: Helm repo `https://charts.bitnami.com/bitnami`, chart `postgresql`,
  pinned `targetRevision`.
- Values: `auth.existingSecret: demo-db`, `auth.database: demo`, 1 Gi PVC,
  modest resources (fit Constitution IV).

## demo-symfony (multi-source)

```yaml
sources:
  - repoURL: <infr-as-a-code>
    path: charts/demo-symfony
    helm:
      valueFiles:
        - $values/clusters/malina/values/demo-symfony.yaml
  - repoURL: <infr-as-a-code>
    targetRevision: main
    ref: values
```

Guarantees:
- The chart carries sane defaults; the environment file carries this cluster's
  choices, including the release tag.
- Jenkins never touches the chart — only `image.tag` in the values file.

## Sync waves (startup order)

| Wave | Component | Why |
|------|-----------|-----|
| 0 | namespaces, secrets (bootstrap-created) | must exist first |
| 1 | `demo-postgres` | database before app |
| 2 | `demo-symfony` | app starts, connects to DB service DNS name |

(Implemented with `argocd.argoproj.io/sync-wave` annotations where needed.)
