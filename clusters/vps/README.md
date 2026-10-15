# VPS cluster

`vps` is the standalone Debian/k3s cluster for `igou.io` and Gotify.
Only manifests installed on the VPS live here. The dedicated
OpenShift Argo CD instance `vps` in `vps-gitops` reconciles remote workloads.
The existing OpenShift instance owns secret delivery through its
`openshift-gitops/vps-secrets` Application. The VPS runs one ESO controller,
NGINX Gateway Fabric and the Tailscale operator. Argo CD, cert-manager,
Connect, MetalLB and monitoring servers remain off-host. Do not include `groups/all`.

- `seed/`: only the `argocd` namespace and cluster-admin `argocd/argocd-manager`
  ServiceAccount, binding and generated-token Secret. AAP submits only this
  bundle through the Kubernetes API, reading the native system:admin kubeconfig
  into memory. It stages no manifest or Secret files. No workload is seeded.
- `bootstrap/`: adopts the access seed and creates the platform/application
  namespaces at wave 0. Add new workload namespaces here; AAP need not run again.
- `monitoring/`: the dedicated metrics-reader identity and scoped proxy access;
  its namespace and the `kube-state-metrics` namespace are also GitOps-owned.
- `kube-state-metrics/`: the official Prometheus community chart, restricted to
  the collectors needed for node, workload and PVC state.
- `external-secrets-operator/` and `external-secrets-config/`: one ESO controller
  and the local mirrored-Secret ClusterSecretStore.
- `nginx-gateway-fabric/`, `tailscale-operator/` and
  `node-exporter/`: the other pinned cluster components.
- `gateway-api/`: mirrored TLS ExternalSecret, public Gateway and redirects.
- `igou-io/` and `gotify/`: application Deployments, Services, HTTPRoutes,
  NetworkPolicies, and Gotify's local PVC/ExternalSecret.
- `migration/`: one-time Gotify restoration Job, excluded from the normal root.
  It refuses a nonempty destination and mounts only protected staged Gotify data.

OpenShift PushSecrets mirror `vps-public-tls`, `vps-tailscale` and `vps-gotify`
into the VPS `external-secrets` namespace. Local `ClusterSecretStore/local-mirrors`
reads that namespace using TokenRequest authentication as `mirror-reader`.
Its reader can only read mirror Secrets and review its permissions; its consumer
namespace allowlist is `nginx-gateway`, `tailscale` and `gotify`. Local
ExternalSecrets create the final application Secrets. OpenShift uses the seeded
cluster-admin Argo credential for remote pushes as well as remote registration;
`remoteNamespace` controls delivery and does not restrict that token's privileges.
The generated token, CA and admin kubeconfig are published to `lab_agents/vps-k3s`;
the admin kubeconfig stays in the management vault. No `eso_token` is generated.

OpenShift cert-manager issues and renews a dedicated certificate for `igou.io`
and `*.igou.io`. The Cloudflare token and ACME account stay in OpenShift.
PushSecret sends a single JSON `bundle` containing `tls.crt` and `tls.key`
to the Opaque `external-secrets/vps-public-tls` mirror. Local ESO renders
`nginx-gateway/gateway-public-tls` as `kubernetes.io/tls`; the Gateway's
certificate reference is unchanged. Each hop refreshes every five minutes.
Existing mirrors and TLS Secrets are retained if delivery stops. Public HTTPS
continues until the installed certificate expires; renewal delivery depends
on OpenShift and Tailscale. No DNS API credential or ACME controller runs here.

The private API is reached through OpenShift's
`vps-k3s-api.vps-secrets.svc.cluster.local:6443` Tailscale egress Service.
The host has `tag:vps`, the operator `tag:vps-operator`, and optional service
proxies default to `tag:vps-app`. API proxy mode is off. Public web ingress
uses ports 80/443; the public-interface guard blocks API and metrics access.

The OpenShift controller definitions and Application catalog live in
`igou-openshift/clusters/ocp/vps-gitops/` and `clusters/ocp/vps/`; registration,
egress and source/push Secrets live in `clusters/ocp/vps-secrets/` there.

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
Argo installs ESO at wave 3, the local store at 4, NGINX at 6,
Tailscale at 8 and the Gateway at 10. Credentials synchronize independently;
verify mirror and local ExternalSecret readiness before application acceptance.

The separate `node-exporter` Application renders the Prometheus community
`prometheus-node-exporter` chart `4.60.0` at wave 10, with non-root
host-network/host-PID access and read-only host mounts. The image digest and
resource limits remain pinned in its Kustomization. Ansible does not manage
an exporter service on the VPS.
OpenShift monitoring retains its existing Tailscale scrape endpoint.

OpenShift UWM also scrapes k3s `/metrics`, kubelet cAdvisor and the
kube-state-metrics/NGINX Services through the existing private API egress path.
The metrics-reader ServiceAccount and generated token live in `monitoring`.
Central ESO imports only its token/CA into OpenShift `tailscale/vps-metrics`;
Prometheus does not use the Argo cluster-admin token. Its permissions cover
`/metrics`, the named `vps` node proxy and the named metrics Service proxies.
Node proxy access is broader than a metrics-only permission; protect this token.
No new public listener, host configuration or local Prometheus is required.

The default Tailscale ProxyClass `metrics` enables client metrics and disables
debug endpoints for future service proxies, retaining `tag:vps-app` as the
default tag. It creates no proxies by itself. There is no Prometheus operator
on the VPS, so the class does not request local ServiceMonitor creation.
OpenShift monitors public HTTP and HTTPS for `igou.io`, `www.igou.io` and
`gotify.igou.io` with its existing blackbox exporter.

The architecture, migration acceptance checks, resource measurements and
legacy AAP retirement live in
`igou-docs/kubernetes/VPS Kubernetes Architecture and Migration.md`.

Manifest files use `<metadata.name>-<kind>.yaml`, with `-pvc.yaml` for PVCs,
as defined by `igou-openshift/CODE_STANDARDS.md`. Local objects use purpose
names (`public`, `gateway-public-tls`, `argocd-manager`,
`mirror-reader`).
