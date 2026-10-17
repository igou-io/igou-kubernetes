# VPS forwarding chart

This reusable chart creates a Tailscale egress Service, a bridge in the
operator's namespace, a named ReferenceGrant, proxy ingress policy, and native HTTPRoute, TCPRoute,
or UDPRoute objects. The empty default service list renders nothing.

The three complete sharing examples live in `examples/public-services/http`,
`tcp`, and `udp` at the repository root. They pair with the three workloads in
`igou-openshift/test-workloads/public-services/` and use plain manifests so
the native routes and supporting objects are visible together. Those examples
are the manual entry point; the chart remains available for reusable Helm
configuration. Do not manage the same forwarding object through both sources.

Each service entry declares its tailnet FQDN and ports. Port `protocol` is
`HTTP`, `TCP`, or `UDP`; HTTP also requires public `hostnames`. Every port names
an existing Gateway listener. HTTP hostnames can share an HTTPS listener;
each TCP/UDP route needs its own listener. Backend ports are independent of
public listener ports. Review `values.schema.json` for the accepted values.

`proxyNamespace` must match the Tailscale operator's namespace. The bridge
selects its exact parent Service name and namespace. The chart uses the VPS
`metrics` ProxyClass by default. If using Argo, ignore `/spec/externalName` on
the generated egress Services because Tailscale owns that field.

AAP creates temporary forwarding with the same native route kinds, plus
expiration metadata. Its scheduled cleanup runs hourly. Runtime AAP objects
must not also be reconciled by Argo. Baseline RBAC is in
`clusters/vps/public-sharing`; the platform listener pool is TCP 27010–27017
and UDP 27018–27025. See `examples/public-services/README.md` for the paired
examples, prerequisites, and manual checks.
