# Tasks: Deploy confirmation (spec 005)

- [x] T001 `clusters/malina/infrastructure/jenkins-rbac.yaml`: SA
  `jenkins-agent` (ns jenkins) + Role/RoleBinding `deploy-watcher`
  (get/list/watch Deployments, ns demo) + Role/RoleBinding
  `argocd-app-refresher` (get/patch/update Applications, ns argocd)
- [x] T002 `10-install-platform.sh`: apply `jenkins-rbac.yaml`
- [x] T003 `ciPipeline.groovy`: agent pod runs as
  `serviceAccountName: jenkins-agent`; new `kubectl` container
  (bitnami/kubectl, arm64); new final `Deploy` stage (refresh ArgoCD app,
  wait for image tag, `rollout status`); new optional `config.deploy`
  map `[namespace, deployment, argoApp]`; updated post messages
- [x] T004 app repo `demo-symfony-k3s/Jenkinsfile`: pass `deploy:` params
- [x] T005 Docs: FROM-SCRATCH.md §9 pipeline row + §8.7; pointer notes in
  spec 001/002 pipeline contracts
- [x] T006 Live: re-run platform script fragment (apply RBAC), push infra
  + app, webhook build goes green including the Deploy stage
  (build #3, 2026-10-25: console shows the tag wait + rollout confirmation)

## Verification

T006: one real release build; console shows `Waiting for deployment …`,
the watched tag, and `deployment "demo-symfony" successfully rolled out`.
