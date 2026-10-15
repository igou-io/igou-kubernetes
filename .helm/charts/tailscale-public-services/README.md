# VPS forwarding to OpenShift

This chart creates a Tailscale egress Service, a bridge in the operator's
namespace, named ReferenceGrants, and HTTPS/TCP/UDP routes. The default empty
service list renders nothing. It does not register an Application or publish
a port by itself.

Render the example, which matches the OpenShift chart's example values:

```bash
helm template public-services .helm/charts/tailscale-public-services \
  -f .helm/charts/tailscale-public-services/examples/arena-values.yaml
```

Each service names a full tailnet MagicDNS endpoint and its backend ports.
Port `protocol` is `HTTP`, `TCP`, or `UDP`; HTTP is forwarded over TCP and
requires public `hostnames`. Each port names an existing Gateway listener.
Multiple HTTP hostnames can share a listener; each TCP/UDP route needs its
own listener. The example uses HTTPS 443, TCP 27015, and UDP 27016.

Adoption also requires:

- Create the `public-services` namespace in `clusters/vps/bootstrap`, with
  `vps.igou.io/public-ingress: 'true'`. Permit this namespace in OpenShift's
  VPS AppProject and register the new VPS Application there after its sources merge.
- Include the local chart in a VPS Kustomization without a top-level
  `namespace` transformer: its bridge and ReferenceGrant belong in `tailscale`.
- Add the TCP/UDP listeners to `clusters/vps/gateway-api/public-gateway.yaml`
  and their container/host port mappings to the NGINX chart. Retain 80/443,
  redirects, resource limits, and the existing rollout strategy.
- Set application-specific tailnet grants from `tag:vps-public-egress` to
  the OpenShift endpoint tags and exact ports. Authorize tag creation by the
  operator clients. This chart does not change policy or OAuth credentials.
- Configure DNS, Ansible-managed firewall allowances, and NetworkPolicies
  for the selected application. Keep the API, metrics, and other management
  ports private. Review proxy ingress rules for Tailscale's UDP peer traffic
  as well as the application ports.
- Ignore only `/spec/externalName` for the generated `ocp-<name>` egress
  Services in the Argo Application; that field belongs to Tailscale.

`proxyNamespace` must match the operator's namespace. The bridge selects both
the parent Service name and namespace so identically named Services elsewhere
cannot match. The chart uses the VPS's existing `metrics` ProxyClass by default;
review proxy memory use before adding many endpoints to the 2 GiB host.

HTTP backend traffic crosses an encrypted tailnet connection. Public user
authentication remains the application's responsibility. Verify forwarded
header handling, WebSockets, real TCP connections, and UDP replies before
opening production access. TLS passthrough can use a TCP route with TLS
terminated by the application. Backend TLS verification is outside this chart.

The design and rollout checks are in igou-docs:
`networking/Tailnet Access Model - Tailscale Operators on Both Clusters.md`.

Run the render regression tests with the repository's development dependencies:

```bash
python3 -m venv .venv
.venv/bin/pip install -r requirements-dev.txt
make test-public-services PYTHON=.venv/bin/python
```
