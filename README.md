# igou-kubernetes

GitOps configuration for my vanilla Kubernetes homelab clusters, following the
same app-of-apps layout as [igou-openshift](https://github.com/igou-io/igou-openshift),
but deploying platform operators from their official upstream Helm charts
instead of OLM.

## Layout

```
.helm/charts/argocd-app-of-app/  Helm chart that templates Argo CD Applications/AppProjects
clusters/<name>/                 Per-cluster GitOps root (values.yaml lists that cluster's apps)
components/                      Reusable platform components (namespace + kustomize + upstream helm chart)
groups/all/                      Kustomize component with AppProjects + baseline apps every cluster gets
docs/                            Operational docs
```

Every component directory is a `kustomization.yaml` that pulls an upstream
Helm chart via kustomize's `helmCharts` field, plus any raw manifests
(namespace, RBAC, ExternalSecrets). Argo CD renders them with
`kustomize build --enable-helm`.

## Components

| Component | Source | Sync wave |
|---|---|---|
| argocd | argoproj.github.io/argo-helm | 0 |
| external-secrets-operator | charts.external-secrets.io | 0 |
| cert-manager | charts.jetstack.io | 5 |
| nginx-gateway-fabric | ghcr.io/nginx/charts (OCI) | 6 |
| democratic-csi | democratic-csi.github.io/charts | 7 |
| kube-prometheus-stack | prometheus-community.github.io/helm-charts | 10 |
| loki | grafana.github.io/helm-charts | 11 |
| tailscale-operator | pkgs.tailscale.com/helmcharts | 12 |
| kubevirt | upstream release manifests (kustomize) | 50 |

Not yet configured (intentionally):

- **democratic-csi** ships with no StorageClasses and references driver config
  secrets (`democratic-csi-{nfs,iscsi}-config`) that don't exist yet.
- **external-secrets** has no ClusterSecretStore; the `onepassword` store and
  its backend still need to be wired up. Until then anything that consumes an
  ExternalSecret (tailscale-operator oauth, private repo creds) stays degraded.

## Bootstrap

See [docs/bootstrap.md](docs/bootstrap.md).

## Validation

```
make test   # yamllint, helm lint, kustomize build, kubeconform
```
