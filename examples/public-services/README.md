# VPS sharing examples

These three native Gateway API examples match the three workloads in
`igou-openshift/test-workloads/public-services/`. Each folder contains a route,
Tailscale egress Service, bridge Service, named ReferenceGrant, and proxy
ingress policy allowing the Gateway namespace on the backend port. They use
distinct backend endpoints and can be installed together.

| Example | Native route | Public listener | OpenShift workload | Backend |
| --- | --- | --- | --- | --- |
| `http/` | `HTTPRoute` | HTTPS 443, `web-test.igou.io` | `http/public-web-test` | TCP 8080 |
| `tcp/` | `TCPRoute` | TCP 27010, `tcp-test.igou.io` | `tcp/tcp-hostname` | TCP 9000 |
| `udp/` | `UDPRoute` | UDP 27018, `udp-test.igou.io` | `udp/udp-echo` | UDP 9000 |

Render one example or all three:

```bash
kustomize build examples/public-services/tcp
kustomize build examples/public-services
```

The examples are staged and have no registered Argo Applications. The VPS
platform must first provide the namespaces, Tailscale operator, `metrics`
ProxyClass, public Gateway, experimental route CRDs, listener/host-port pool,
and HTTPS certificate. OpenShift provides the matching workload and stable
Tailscale endpoint. Configure DNS, tailnet tag ownership/grants, and the host
firewall before public checks. Open only the selected public listener ports;
tailnet grants use the backend ports in the table.

If adopting an example through Argo, ignore `/spec/externalName` on its
Tailscale egress Service in `public-services`; the operator owns that field.
The bridge selects only the proxy for its exact parent Service and namespace.
The named ReferenceGrant permits only the matching route kind to reference
that bridge in `tailscale`. The ingress policy selects only that bridge
proxy and permits the Gateway namespace on the selected backend port.

These are static sharing examples. The AAP catalog has matching `http`, `tcp`,
and `udp` backends and creates its own temporary forwarding objects with
expiration metadata. Use AAP for expiring shares; choose free TCP/UDP listeners
when the static examples already occupy the example ports.
