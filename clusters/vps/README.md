# VPS cluster

`vps` is the standalone Debian/k3s cluster for `igou.io` and Gotify.
All cluster resources and its OpenShift-side management manifests live here.
OpenShift Argo CD reconciles them; no Argo CD, ESO, MetalLB, or monitoring
server is installed on the VPS. Do not include `groups/all` in this root.

- `bootstrap/`: VPS namespaces, dedicated Argo deployment identity, and a
  separate ESO writer restricted to three namespaces. Bootstrap generates
  service-account credentials; their values never enter Git.
- `bootstrap-management/`: initial OCP root Application and AppProject.
- `management/`: OCP API egress, ExternalSecrets, remote SecretStores,
  PushSecrets, and the remote Argo cluster registration.
- `platform/`: pinned cert-manager, NGINX Gateway Fabric, and Tailscale operator.
- `gateway/`: DNS-01 issuer, certificate, shared Gateway, and redirects.
- `applications/`: the static website image, Gotify, local PVC, and network policies.
- `migration/`: one-time Gotify restoration Job, deliberately excluded from
  the normal root. It refuses a nonempty destination and mounts only the
  protected staged Gotify data directory.

The API endpoint is private host Tailscale, reached by OCP through
`vps-k3s-api.tailscale.svc.cluster.local:6443`. The host has `tag:vps`,
the operator has `tag:vps-operator`, and service proxies default to
`tag:vps-app`. API proxy mode is off. Creating a public Gateway does not expose
the Kubernetes API.

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
