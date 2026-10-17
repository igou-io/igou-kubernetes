# Native TCPRoute example

These plain Kubernetes manifests forward VPS TCP 27010 through the public
Gateway and Tailscale to OpenShift's `public-web-test` on TCP 8080. They match
the chart's `web-test-tcp-values.yaml` example and are an alternative way to
manage the same objects. Choose one owner for these resources.

`web-test-tcp-tcproute.yaml` is the native Gateway API `TCPRoute`. It attaches
to `nginx-gateway/public` listener `tcp-27010` and references the bridge Service
in `tailscale`. The named `ReferenceGrant` permits that reference; the bridge
selects the proxy belonging to the Tailscale egress Service in `public-services`.

Render the example from the repository root:

```bash
kustomize build .helm/charts/tailscale-public-services/examples/native-tcp
```

The OpenShift workload, its Tailscale endpoint, VPS namespaces/operators,
Gateway listener, host-port mapping, DNS, firewall, and tailnet grants are
prerequisites. Their owning platform configuration remains separate. This
example is staged and is not registered as an Argo Application. If adopting
it through Argo, ignore `/spec/externalName` on `public-services/ocp-web-test`
because the Tailscale operator owns that field.

After rollout, check from outside the tailnet:

```bash
curl --fail http://web-test.igou.io:27010/
```

Expect `public-services web test`. HTTP is the sample payload carried by this
TCP connection; the Gateway forwards bytes through the `TCPRoute`. Verify
the route's `Accepted` and `ResolvedRefs` conditions before checking traffic.
