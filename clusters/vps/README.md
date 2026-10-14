# VPS cluster

`vps` is the standalone Debian/k3s cluster for `igou.io` and Gotify.
Its manifests and OpenShift management resources live here. The dedicated
OpenShift Argo CD instance `vps` in `vps-gitops` reconciles remote workloads.
The existing OpenShift instance owns secret delivery through its
`openshift-gitops/vps-secrets` Application. The VPS runs one ESO controller,
cert-manager, NGINX Gateway Fabric and the Tailscale operator. Argo CD,
Connect, MetalLB and monitoring servers remain off-host. Do not include `groups/all`.

- `seed/`: eight namespaces and the cluster-admin `argocd/argocd-manager`
  ServiceAccount, binding and generated-token Secret. AAP applies only this
  bundle using the root-owned system:admin kubeconfig. No workload is seeded.
- `bootstrap/`: adopts the seed and adds the node-exporter DaemonSet through Argo.
- `bootstrap-management/`: OpenShift namespaces, dedicated Argo CD instance,
  its initial root Application/AppProject and the existing instance's
  `vps-secrets` Application. OCP owns this through its `vps-gitops` pointer.
- `management/`: API egress in OpenShift `vps-secrets`, remote registration in
  `vps-gitops`, and source ExternalSecrets/PushSecrets plus the connection
  Secret and remote SecretStore in `openshift-gitops`.
- `external-secrets-operator/` and `external-secrets-config/`: one ESO controller
  and the local mirrored-Secret ClusterSecretStore.
- `cert-manager/`, `nginx-gateway-fabric/`, `tailscale-operator/` and
  `node-exporter/`: the other pinned cluster components.
- `gateway-api/`: DNS credential, issuer, certificate, public Gateway and redirects.
- `igou-io/` and `gotify/`: application Deployments, Services, HTTPRoutes,
  NetworkPolicies, and Gotify's local PVC/ExternalSecret.
- `migration/`: one-time Gotify restoration Job, excluded from the normal root.
  It refuses a nonempty destination and mounts only protected staged Gotify data.

OpenShift PushSecrets mirror `vps-cloudflare`, `vps-tailscale` and `vps-gotify`
into the VPS `external-secrets` namespace. Local `ClusterSecretStore/local-mirrors`
reads that namespace using TokenRequest authentication as `mirror-reader`.
Its reader can only read mirror Secrets and review its permissions; its consumer
namespace allowlist is `cert-manager`, `tailscale` and `gotify`. Local
ExternalSecrets create the final application Secrets. OpenShift uses the seeded
cluster-admin Argo credential for remote pushes as well as remote registration;
`remoteNamespace` controls delivery and does not restrict that token's privileges.
The generated token, CA and admin kubeconfig are published to `lab_agents/vps-k3s`;
the admin kubeconfig stays in the management vault. No `eso_token` is generated.

The private API is reached through OpenShift's
`vps-k3s-api.vps-secrets.svc.cluster.local:6443` Tailscale egress Service.
The host has `tag:vps`, the operator `tag:vps-operator`, and optional service
proxies default to `tag:vps-app`. API proxy mode is off. Public web ingress
uses ports 80/443; the public-interface guard blocks API and metrics access.

The dedicated Argo instance has its own server, controller, repo server, Redis,
OpenShift OAuth and Route at `https://vps-argocd.apps.ocp.igou.systems`.
Its local namespace rights cover `vps-gitops` only. Keep it out of
`ARGOCD_CLUSTER_CONFIG_NAMESPACES`; only its remote VPS deployment credential
is cluster-admin. Annotation tracking uses installation ID `vps`, ApplicationSet
is disabled, and Helm rendering and child Application health are configured.

The website pins a public `quay.io/igou/igou.io:vps` digest. CI publishes successful
master builds; Renovate proposes digest updates. Application auto-sync starts
disabled until the website is verified and Gotify's PVC is restored before startup.
Host provisioning uses `vps_bootstrap_host` and `vps_publish_access` in AAP.
Argo installs ESO at wave 3, the local store at 4, cert-manager at 5, NGINX at 6,
Tailscale at 8 and the Gateway at 10. Credentials synchronize independently;
verify mirror and local ExternalSecret readiness before application acceptance.

Node-exporter runs as a non-root host-network/host-PID DaemonSet with read-only
host mounts. Argo owns it; AAP stops and disables any legacy host exporter service.
OpenShift monitoring retains its existing Tailscale scrape endpoint.

The durable architecture, migration acceptance, resource measurements and
legacy AAP retirement live in
`igou-docs/kubernetes/VPS Kubernetes Architecture and Migration.md`.

Manifest files use `<metadata.name>-<kind>.yaml`, with `-pvc.yaml` for PVCs,
as defined by `igou-openshift/CODE_STANDARDS.md`. Local objects use purpose
names (`cluster-acme`, `public`, `gateway-public-tls`, `argocd-manager`,
`mirror-reader`); shared OpenShift delivery objects keep the `vps` prefix.
