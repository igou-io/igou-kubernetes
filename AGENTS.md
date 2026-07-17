# AGENTS.md

Agent instructions for this repository.

## What This Repo Is

GitOps configuration for vanilla (non-OpenShift) Kubernetes homelab clusters,
following the same ArgoCD app-of-apps layout as
[igou-openshift](https://github.com/igou-io/igou-openshift), but deploying
platform operators from their official upstream Helm charts (via kustomize
`helmCharts`) instead of OLM.

**Cluster naming:** the only cluster today is `clusters/internal/` — this is
the cluster called **`rk8s`** everywhere else (the `rk8s*` inventory groups in
igou-inventory, the k3s-on-ARM-boards cluster in igou-ansible docs, "rk8s" in
igou-openshift federation configs). GitOps dir name `internal` == Ansible
group `rk8s`; they are the same cluster.

## Layout

```
.helm/charts/argocd-app-of-app/  Helm chart that templates Argo CD Applications/AppProjects
clusters/<name>/                 Per-cluster GitOps root (values.yaml lists that cluster's apps)
components/<name>/               Reusable platform components (namespace + kustomize + upstream helm chart)
groups/all/                      Kustomize component with AppProjects + baseline apps every cluster gets
docs/                            Operational docs (bootstrap)
```

- Baseline apps every cluster gets live in `groups/all/values.yaml`
  (argocd, external-secrets-operator, cert-manager, metallb,
  nginx-gateway-fabric); cluster-specific apps and wiring live in
  `clusters/<name>/values.yaml` (and `clusters/<name>/<app>/` for
  cluster-specific manifests like the democratic-csi driver configs).
- Sync waves are `argocd.argoproj.io/sync-wave` annotations in those values
  files. Current ordering: argocd/ESO 0 → cert-manager/metallb 5 → NGF 6 →
  democratic-csi 7 → kube-prometheus-stack 10 → loki 11 →
  tailscale-operator 12 → gateway 15 → headlamp/whoami 16 → kubevirt 50.
- Argo CD renders components with `kustomize build --enable-helm`; CR
  manifests that depend on chart-installed CRDs carry
  `argocd.argoproj.io/sync-options: SkipDryRunOnMissingResource=true`.

## Networking (MetalLB / BGP / Gateway)

The full network design — peer addressing, ASNs, tier split boundaries, the
pinned-VIP registry, and the invariants behind them — lives in the private
inventory repo at `igou-inventory/docs/network-topology.md`. **Read it before
changing anything under `components/metallb/` or `components/gateway/`.**
What an agent needs to know from this side:

- `components/metallb/` peers this cluster with the homelab router over BGP.
  The peer and pool specifics live in those manifests and their header
  comments. The ONE L2 exception is the `vlan9-wildcard` pool (the
  cluster-wildcard ingress VIP `10.10.9.11` — ARP on VLAN9, not BGP); every
  other pool stays BGP-only.
- The MetalLB tier pools are **shared with the OpenShift cluster**
  (`igou-openshift/clusters/ocp/metallb/`): each tier range is split between
  the two clusters, and the router's import filter enforces the split per
  peer. Never widen or move a pool boundary in one repo alone.
- **Two ingress classes** (full policy in the topology doc):
  - `cluster-wildcard` Gateway (`*.rk8s.igou.systems` → `10.10.9.11`):
    zero-friction — rb5009 carries ONE wildcard record, so merging an
    HTTPRoute is the only step to serve. Reachable from VLAN9 + admin.
  - Tier gateways (`trusted-lan` → `*.lan.igou.systems` @ `10.10.150.129`,
    `iot` → `*.iot.igou.systems` @ `10.10.151.129`; ocp owns
    `*.dmz.igou.systems`): intentional serving — every hostname needs an
    explicit A record in igou-inventory + a `routeros_configure` apply.
- All gateway VIPs are pinned cross-repo contracts — the router carries
  matching static DNS and firewall rules in igou-inventory. Never change
  one without a paired igou-inventory change.
- The `metallb` app pins `ServerSideDiff=false` (see comment in
  `groups/all/values.yaml`) so pool-boundary changes survive the MetalLB
  validating webhook during client-side diff.

## Key Conventions

- YAML: 2-space indent, `---` header, `true`/`false` booleans, block style
  (`{}`/`[]` only for genuinely empty values)
- Secrets are ExternalSecrets backed by the `onepassword` ClusterSecretStores
  (`components/external-secrets-operator/`) — never commit secret values
- When adding or moving manifests, update the component's
  `kustomization.yaml`; prefer `<metadata.name>-<kind>.yaml` filenames
- k3s defaults `local-path` as the default StorageClass — PVCs that need
  TrueNAS storage must pin `storageClassName` explicitly

## Validation

```bash
make test   # yamllint, helm lint, kustomize build, kubeconform
```

## Cross-repo pointers

- Node provisioning / k3s install / GitOps bootstrap:
  `igou-ansible/playbooks/kubernetes/` (bootstrap uses
  `gitops_cluster=internal`)
- Inventory and node identities: `igou-inventory` (`rk8s*` groups; board
  nodes hold static DHCP reservations the router's BGP filter depends on)
- Router half of the BGP/DNS/firewall contract:
  `igou-inventory/host_vars/` (router config) +
  `igou-inventory/docs/network-topology.md` (design doc)
- The peer OpenShift cluster's MetalLB config:
  `igou-openshift/clusters/ocp/metallb/`
