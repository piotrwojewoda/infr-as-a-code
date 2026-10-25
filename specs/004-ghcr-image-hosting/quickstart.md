# Quickstart: Migrating Image Hosting to GHCR

**Feature**: 004-ghcr-image-hosting | **Date**: 2026-10-25

This runbook moves the live platform from the in-cluster registry to GitHub
Container Registry and validates the result. Prerequisite: operator access to
the Pi and a GitHub PAT with `read:packages`, `write:packages` and `repo`.

## 0. Prepare the token

1. Create or update the PAT used by Jenkins. Scopes: `repo`,
   `read:packages`, `write:packages`.
2. Rotate only the GHCR Secrets (no other secret is touched):

   ```bash
   cd clusters/malina/bootstrap
   export GITHUB_USER=piotrwojewoda
   export GITHUB_TOKEN='<new PAT>'
   bash ghcr-secrets.sh
   ```

   Do **not** re-run the whole `10-install-platform.sh` just to rotate the
   token: it would also regenerate the webhook secret, DB password and admin
   password unless you reuse the previous values.

3. Update the Jenkins credential `github-pat` with the same token if it was
   rotated (Jenkins → Manage Credentials). The pipeline uses that credential
   for the GitOps push, and the `ghcr-push` Secret for the image push.

## 1. Roll out the code

Merge this feature to `main`. ArgoCD applies the values change
(`ghcr.io/...` + `ghcr-pull`) and Jenkins picks up the new shared library on
the next build.

Expected, temporary state: the demo Pod may sit in `ImagePullBackOff` until
the first GHCR image exists. The old ReplicaSet keeps serving traffic.

## 2. Produce the first GHCR image

Trigger one build of `demo-symfony-k3s` (merge a trivial commit or press
"Build now"). Watch the `Build & Push` stage: it must push two tags to
`ghcr.io/piotrwojewoda/demo-symfony-k3s` without `--insecure`.

Then verify:

```bash
kubectl -n demo get pods
kubectl -n demo describe pod -l app.kubernetes.io/name=demo-symfony | grep -i image
```

The new Pod must be `Running`/`Ready` and its image must start with
`ghcr.io/`. The next commit in `infr-as-a-code` bumps `image.tag`.

## 3. One-time cleanup of the old registry

The old registry was never an ArgoCD Application, so this step is manual and
runs once:

```bash
kubectl delete -f clusters/malina/infrastructure/registry.yaml --ignore-not-found
kubectl delete namespace registry --ignore-not-found
```

Remove the containerd insecure mirror if it exists:

```bash
sudo sed -i '/30500/,+2d' /etc/rancher/k3s/registries.yaml
sudo rm -f /etc/rancher/k3s/registries.yaml.bak
sudo systemctl restart k3s
```

If `/etc/rancher/k3s/registries.yaml` is now empty, delete it. Adjust the
`sed` range if the file contains other registries: keep them, remove only the
`30500` mirror block.

Remove the old firewall rule:

```bash
sudo ufw status numbered | grep 30500
sudo ufw delete allow from 192.168.0.0/16 to any port 30500 proto tcp
```

## 4. Validation

| Check | Command | Expected |
|-------|---------|----------|
| Registry workload gone | `kubectl -n registry get all` | `No resources found` |
| Registry port closed | `nc -zv 192.168.68.52 30500` | connection refused |
| Firewall clean | `sudo ufw status \| grep 30500` | no output |
| GHCR package exists | GitHub → Packages → `demo-symfony-k3s` | SHA + `latest` tags |
| Pod pulls from GHCR | `kubectl -n demo get pod -o jsonpath='{.items[0].spec.containers[0].image}'` | `ghcr.io/piotrwojewoda/...` |
| Pipeline works | Jenkins run | `SUCCESS`, tag bumped in git |
| App reachable | `curl -I https://kreciowo.pl` | HTTP 200 |

## 5. Failure modes

| Symptom | Cause | Fix |
|---------|-------|-----|
| Kaniko: `DENIED: permission_denied` | PAT lacks `write:packages` | create a PAT with the scope, re-run step 0 |
| Pod `ImagePullBackOff`, event `unauthorized` | `ghcr-pull` missing/expired | re-run step 0; `kubectl -n demo get secret ghcr-pull` |
| Pod `ImagePullBackOff`, event `manifest unknown` | tag not built yet | run step 2 (first pipeline build) |
| ArgoCD still shows old image | tag bump not pushed / sync lag | check the release commit, hard-refresh the ArgoCD app |
| SD card still growing | old registry namespace/PVC not deleted | run step 3 |
