# Envoy Gateway on rk8s

Spec and operational notes for the `envoy-gateway` component
(Envoy Gateway v1.8.2, Gateway API implementation).

## Goal

Give rk8s a working L7 ingress: a Gateway API data plane answering on the
reserved ingress VIP `10.10.150.129`, which `*.rk8s.igou.systems` and the
`rk8s.igou.systems` apex already resolve to (igou-inventory DNS). Workloads
expose themselves by creating `HTTPRoute` objects that attach to the shared
`rk8s` Gateway.

## Current state this builds on

- nginx-gateway-fabric (NGF) is deployed at wave 6 but idle: its
  GatewayClass `nginx` is Accepted, yet no Gateway or HTTPRoute exists
  anywhere in the cluster, so it runs no data plane and holds no LB service.
- The live Gateway API CRDs are the **standard channel v1.5.1** bundle,
  installed and owned by the NGF app (pinned to the NGF release tag).
- MetalLB (FRR-K8s, BGP to rb5009) is deployed, `trusted-lan-gateway` pool
  reserves `10.10.150.129/32` with `autoAssign: false`, and k3s was
  installed without klipper-lb. No LoadBalancer service exists yet — this
  gateway is the first consumer.
- cert-manager runs with `enableGatewayAPI: true`, but no (Cluster)Issuer
  exists yet.

## Design

### CRD ownership — the one sharp edge

The app-of-apps defaults include `FailOnSharedResource=true`, so exactly one
Argo app may own any given CRD. The Gateway API CRDs stay with the NGF app
(standard channel v1.5.1, matching what is live). Envoy Gateway is therefore
installed in two pieces:

- `gateway-crds-helm` with `crds.gatewayAPI.enabled=false` and
  `crds.envoyGateway.enabled=true` — installs only the
  `gateway.envoyproxy.io` CRDs.
- `gateway-helm` with `crds.enabled=false` — control plane only. Left at
  its default, that chart's crds subchart would install the *experimental*
  Gateway API channel over NGF's standard bundle (plus a
  ValidatingAdmissionPolicy that polices exactly that kind of overwrite).

Envoy Gateway v1.8.2 targets Gateway API v1.5.1, the exact live bundle
version. On the standard channel EG reconciles HTTPRoute and GRPCRoute;
TCPRoute/UDPRoute are experimental-only, and TLSRoute — although present in
standard v1.5.1 as `v1` — is skipped by EG, which still watches the
`v1alpha3` version (envoyproxy/gateway#8326). HTTP(S) routing is unaffected.

**If/when NGF is retired**: move the Gateway API CRDs into a standalone
`gateway-api-crds` component *first*, then remove the NGF app. Deleting the
NGF app while it owns the CRDs risks pruning every `gateways.networking.k8s.io`
resource with them.

### Component layout

Follows the democratic-csi split: generic install in `components/`,
cluster-specific config in `clusters/internal/`.

```
components/envoy-gateway/            # charts, namespace, monitors (portable)
clusters/internal/envoy-gateway/     # GatewayClass + EnvoyProxy + Gateway
                                     # (VIP, hostnames — rk8s-specific)
```

The Argo app (`clusters/internal/values.yaml`, wave 6) points at the
cluster overlay, which includes the component.

### Data plane

- `GatewayClass envoy` → `parametersRef` → `EnvoyProxy rk8s-proxy-config`.
- Envoy Gateway generates the proxy Deployment/Service at runtime in
  `envoy-gateway-system`; they are intentionally not in git and stay
  untracked by Argo.
- The generated Service is `type: LoadBalancer` with
  `metallb.io/loadBalancerIPs: 10.10.150.129` and
  `externalTrafficPolicy: Local` (real client IPs; MetalLB announces the
  VIP only from nodes with a ready proxy pod). 2 replicas, sized for the
  SBC fleet.
- `topologyInjector` disabled — single-zone cluster, one less mutating
  webhook.

### Gateway

One shared `Gateway rk8s` with HTTP listeners for `*.rk8s.igou.systems`
and the apex, `allowedRoutes: All` (project separation is handled at the
Argo project layer, not by listener namespace policy).

TLS is a deliberate follow-up: there is no issuer on rk8s yet. When one
exists, add a 443 listener with `tls.certificateRefs` and a cert-manager
`Certificate` (or Gateway annotation) for `*.rk8s.igou.systems`.

### Monitoring

kube-prometheus-stack selects monitors cluster-wide, so the component ships:

- `ServiceMonitor envoy-gateway` — control-plane metrics :19001.
- `PodMonitor envoy-proxy-fleet` — Envoy stats `:19001/stats/prometheus`
  on the generated proxy pods, matched by the infra-manager labels.

### Argo CD mechanics

- certgen Job + RBAC carry `helm.sh/hook: pre-install` annotations that
  Argo CD executes as PreSync hooks (upstream annotates them for Argo);
  the Job self-cleans via `ttlSecondsAfterFinished: 30`.
- The whole cluster overlay gets
  `argocd.argoproj.io/sync-options: SkipDryRunOnMissingResource=true` so
  first-sync dry-runs don't fail before the EG CRDs register.
- Big EG CRDs are fine because apps default to `ServerSideApply=true`.

## Using it

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: myapp
  namespace: myapp
spec:
  parentRefs:
    - name: rk8s
      namespace: envoy-gateway-system
  hostnames:
    - myapp.rk8s.igou.systems
  rules:
    - backendRefs:
        - name: myapp
          port: 8080
```

## Verification after first sync

```sh
kubectl -n envoy-gateway-system get pods                  # controller + 2 envoy proxies
kubectl get gatewayclass envoy                            # Accepted=True
kubectl -n envoy-gateway-system get gateway rk8s          # Programmed=True, address 10.10.150.129
kubectl -n envoy-gateway-system get svc                   # generated LB svc holds the VIP
curl -H 'Host: anything.rk8s.igou.systems' http://10.10.150.129/   # 404 from Envoy = data path up
```

If the VIP never leaves `<pending>`, check MetalLB speaker logs and the
rb5009 `metallb-in` filter (rk8s may only announce the high /25 of each
tier; `.129` is the low edge of the allowed half).

## Follow-ups

- ClusterIssuer + HTTPS listener + wildcard cert.
- Decide NGF's fate; if retiring it, do the `gateway-api-crds` component
  extraction first (see above).
- Confirm the PodMonitor actually produces targets (the proxy pods must
  expose 19001; if not, switch to a scrape config on the
  `prometheus.io/*` annotations EG stamps on proxy pods).
