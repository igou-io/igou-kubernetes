# AGENTS.md

Agent instructions for this repository.

## What This Repo Is

GitOps configuration for vanilla (non-OpenShift) Kubernetes homelab clusters,
following the same ArgoCD app-of-apps layout as
[igou-openshift](https://github.com/igou-io/igou-openshift), but deploying
platform operators from their official upstream Helm charts (via kustomize
`helmCharts`) instead of OLM.

**Cluster naming:** `clusters/internal/` is **`rk8s`** (the ARM cluster and
`rk8s*` inventory groups). `clusters/vps/` is the standalone Debian cluster
**`vps`**. It contains only objects installed on the VPS, including its seed,
platform controllers and workloads. OpenShift-hosted Argo CD, Applications,
AppProjects, remote registration, API egress and central secret delivery belong
in `igou-openshift/clusters/ocp/{vps-gitops,vps,vps-secrets}/`. The dedicated
OpenShift Argo CD instance `vps` in `vps-gitops` reconciles the remote VPS
manifests from this repository; its Application catalog lives in igou-openshift.
Do not import `groups/all` into the VPS root: that group installs local
Argo CD, full ESO defaults, MetalLB, and homelab services. The VPS runs a
single ESO controller with its own local mirrored-Secret provider. OpenShift
cert-manager owns public certificate issuance and renewal; only the TLS bundle
is delivered to the VPS, whose Gateway consumes a local ESO-managed TLS Secret.

## Layout

```
.helm/charts/argocd-app-of-app/  Helm chart that templates Argo CD Applications/AppProjects
clusters/<name>/                 Per-cluster GitOps root (values.yaml lists that cluster's apps)
components/<name>/               Reusable platform components (namespace + kustomize + upstream helm chart)
groups/all/                      Kustomize component with AppProjects + baseline apps every cluster gets
igou-docs/kubernetes/             Operational docs (companion repo)
```

- Baseline apps every cluster gets live in `groups/all/values.yaml`
  (argocd, external-secrets-operator, cert-manager, metallb,
  nginx-gateway-fabric); cluster-specific apps and wiring live in
  `clusters/<name>/values.yaml` (and `clusters/<name>/<app>/` for
  cluster-specific manifests like the democratic-csi driver configs).
- Sync waves are `argocd.argoproj.io/sync-wave` annotations in those values
  files. Current ordering: argocd/ESO 0 → cert-manager/metallb 5 → NGF/snapshot-controller 6 →
  democratic-csi 7 → kube-prometheus-stack 10 → loki 11 →
  tailscale-operator 12 → gateway 15 → headlamp/whoami 16 → kubevirt 50.
- Argo CD renders components with `kustomize build --enable-helm`; CR
  manifests that depend on chart-installed CRDs carry
  `argocd.argoproj.io/sync-options: SkipDryRunOnMissingResource=true`.

## Networking (MetalLB / BGP / Gateway)

The full network design — peer addressing, ASNs, tier split boundaries, the
pinned-VIP registry, and the invariants behind them — lives in the central vault at `igou-docs/networking/Network Fabric - VLANs, VIPs, BGP, and MetalLB Tiers.md`. **Read it before
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
- Keep ordinary strings unquoted. Quote values that must remain strings
  when YAML would interpret them as numbers, booleans, or null; also quote
  wildcard selectors and template expressions. Put a list item's first
  field on the same line as its dash, as in `- name: example`.
- Secrets are ExternalSecrets backed by the `onepassword` ClusterSecretStores
  (`components/external-secrets-operator/`) on rk8s. VPS ExternalSecrets use
  `ClusterSecretStore/local-mirrors`, reading OpenShift-mirrored Secrets in
  `external-secrets`; no Connect credential on the VPS. Never commit secret values
- Follow `igou-openshift/CODE_STANDARDS.md` for authored manifests: one object
  per file, named `<metadata.name>-<lowercase-kind>.yaml`; use `-pv.yaml` and
  `-pvc.yaml` for volumes/claims. Update the nearest `kustomization.yaml`.
- Under `clusters/vps/`, use component directories and purpose-named resources.
  Define its component-named Argo Applications in igou-openshift, where they run.
  Keep every object destined for OpenShift in that repository.
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
  `igou-docs/networking/Network Fabric - VLANs, VIPs, BGP, and MetalLB Tiers.md` (design doc)
- The peer OpenShift cluster's MetalLB config:
  `igou-openshift/clusters/ocp/metallb/`

## Documentation ownership

Operational runbooks and durable architecture decisions belong in
`/workspace/igou-docs`. Keep implementation plans in the conversation; if a
persistent record is needed, write a concise decision note in that vault.
Do not create `docs/superpowers/` or repository-local agent execution plans.
Keep public API/collection documentation, READMEs, and agent instructions
beside the code. Update the relevant vault note when behavior changes.
