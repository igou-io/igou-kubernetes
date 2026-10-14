# VPS cluster

`vps` is the standalone Debian/k3s cluster for `igou.io` and Gotify.
All cluster resources and its OpenShift-side management manifests live here.
The dedicated OpenShift Argo CD instance `vps` in `vps-gitops` reconciles
them; no Argo CD, ESO, MetalLB, or monitoring
server is installed on the VPS. Do not include `groups/all` in this root.

- `bootstrap/`: VPS namespaces, dedicated Argo deployment identity, and a
  separate ESO writer restricted to three namespaces, and the node-exporter
  DaemonSet. Bootstrap generates
  service-account credentials; their values never enter Git.
- `bootstrap-management/`: OpenShift namespaces, the dedicated Argo CD
  instance, and its initial root Application/AppProject. The existing OCP
  instance owns these resources through its `vps-gitops` Application.
- `management/`: OCP API egress, ExternalSecrets, remote SecretStores,
  PushSecrets, and the remote Argo cluster registration.
- `platform/`: pinned cert-manager, NGINX Gateway Fabric, Tailscale operator,
  and node-exporter. The bootstrap Application owns node-exporter so it is
  available for the k3s baseline before platform/application rollout.
- `gateway/`: DNS-01 issuer, certificate, shared Gateway, and redirects.
- `applications/`: the static website image, Gotify, local PVC, and network policies.
- `migration/`: one-time Gotify restoration Job, deliberately excluded from
  the normal root. It refuses a nonempty destination and mounts only the
  protected staged Gotify data directory.

The API endpoint is private host Tailscale, reached by OCP through
`vps-k3s-api.vps-secrets.svc.cluster.local:6443`. The host has `tag:vps`,
the operator has `tag:vps-operator`, and service proxies default to
`tag:vps-app`. API proxy mode is off. Creating a public Gateway does not expose
the Kubernetes API.

The dedicated instance has its own server, controller, repo server, Redis,
OpenShift OAuth and Route at `https://vps-argocd.apps.ocp.igou.systems`.
Its local namespace access is limited to `vps-gitops` and `vps-secrets`;
`vps-secrets` is labeled for the GitOps Operator to grant namespace permissions.
Keep it out of `ARGOCD_CLUSTER_CONFIG_NAMESPACES`: only the remote VPS
registration uses a privileged deployment token. Its annotation tracking has
installation ID `vps`. ApplicationSet is disabled; Kustomize Helm rendering
and child Application health are configured for this app-of-apps root.

The website uses a digest of the public `quay.io/igou/igou.io:vps` image.
Renovate discovers digest changes; CI publishes only successful master builds.
Application auto-sync is initially disabled for the migration. Enable it after
the website is verified and Gotify's PVC is restored before first startup.

Host provisioning is AAP/Ansible-managed (`vps_bootstrap_host` and
`vps_publish_access`). The privileged Argo identity manages platform RBAC;
the ESO identity cannot mutate workloads or read `kube-system` Secrets.
Generated credentials and keys remain protected on the host and in 1Password.

The architecture, cutover acceptance, resource measurements, recovery policy,
and legacy AAP retirement are owned by
`igou-docs/kubernetes/VPS Kubernetes Architecture and Migration.md`.

Node-exporter is a non-root host-network/host-PID pod with read-only host
mounts. The host public-interface guard blocks port 9100; central OpenShift
monitoring keeps the existing Tailscale endpoint. No host exporter service or
local Prometheus instance is installed. The host bootstrap disables a legacy
exporter service if present.
