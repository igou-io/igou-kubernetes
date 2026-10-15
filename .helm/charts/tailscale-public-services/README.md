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

The VPS platform configuration includes the `public-services` namespace,
namespace-scoped AAP identity, and a fixed pool: TCP 27010–27017 and UDP
27018–27025. Gateway listeners are named `tcp-<port>` and `udp-<port>`, with
matching host-port mappings. The example above is manual wiring with dedicated
`arena-tcp`/`arena-udp` listener names; provide those listeners or change its
values to use the fixed pool.

The AAP implementation is in `igou-ansible/playbooks/kubernetes/public-share.yaml`.
It creates equivalent temporary Services, grants, policies, and routes with
expiration metadata. Its scheduled cleanup runs hourly. Those runtime objects
must not also be reconciled by Argo. The platform RBAC lives in
`clusters/vps/public-sharing` and is registered by OpenShift's VPS catalog.

Before publishing, configure the exact Tailscale publication grants and operator
tag ownership, DNS, and the approved OpenShift endpoint. Keep management ports
private. If adopting this chart directly through Argo instead of AAP, ignore
only `/spec/externalName` on generated egress Services because Tailscale owns it.

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
