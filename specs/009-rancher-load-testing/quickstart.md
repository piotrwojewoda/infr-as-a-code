# Quickstart: Rancher and kube-burner

## Rancher

1. Point `rancher.kreciowo.pl` at `192.168.68.52` in LAN DNS or the hosts file.
2. Open `https://rancher.kreciowo.pl` from the LAN. The initial certificate is
   self-signed because the purchased certificate does not cover this hostname.
3. Read the generated initial password:

   ```bash
   kubectl -n cattle-system logs -l app=rancher | grep -i 'Bootstrap Password:'
   ```

4. Log in as `admin`, set a permanent password, and store it in a password
   manager. The `local` cluster is registered automatically.

## Run a load test

Start with the safe defaults: five pods, 60 seconds, 2 API requests/second.

1. In `clusters/malina/values/kube-burner.yaml`, set `workload.enabled: true`
   and choose a new `runID` (for example `002`). Commit and push to `main`.
2. Watch the run and Grafana dashboard:

   ```bash
   kubectl -n load-testing get jobs,pods
   kubectl get pods -n kube-burner-load -w
   # In another terminal:
   kubectl -n load-testing logs -f job/kube-burner-002
   ```

3. The pods consume CPU for `cpuSeconds`; kube-burner then deletes the
   `kube-burner-load` namespace. Verify:

   ```bash
   kubectl get namespace kube-burner-load
   ```

   Expected after completion: `NotFound`.
4. Set `workload.enabled: false`, commit and push. ArgoCD prunes the completed
   Job. Always increment `runID` for the next run instead of editing a Job that
   already ran.

To increase load, change `iterations`, `replicas`, `cpuSeconds`, `qps` and
`burst` gradually. Each default pod can consume 100m CPU. Do not run a test
while Jenkins builds or other important work needs the Pi.
