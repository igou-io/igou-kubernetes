# Bootstrapping a cluster

Two manual steps; everything after is reconciled by Argo CD.

## 1. Install Argo CD

```sh
kustomize build --enable-helm components/argocd | kubectl apply --server-side -f -
```

`--server-side` is required: some upstream CRDs (kube-prometheus-stack,
external-secrets) exceed the client-side annotation size limit.

## 2. Apply the cluster root

```sh
kustomize build --enable-helm clusters/internal | kubectl apply -f -
```

This creates the AppProjects and all Application CRs, including the
`app-of-apps` Application that points back at `clusters/internal` — from that
point the cluster self-manages, and adding an app is just a new entry in
`clusters/internal/values.yaml` (or `groups/all/values.yaml` for things every
cluster should get).

## Notes

- Argo CD is configured with `kustomize.buildOptions: --enable-helm`; every
  path in this repo is rendered as kustomize + inline Helm charts.
- The `argocd` Application manages Argo CD itself after bootstrap, so the
  manual install from step 1 is adopted and kept in sync from git.
- Until a `ClusterSecretStore` named `onepassword` exists, ExternalSecrets
  (tailscale oauth, private repo credentials) will report degraded — expected
  until the secrets backend is configured.
