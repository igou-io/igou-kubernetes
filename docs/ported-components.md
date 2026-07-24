# Ported components — OpenShift → rk8s migration readiness

Inert, ready-to-adopt ports of the igou-openshift platform stacks, authored
2026-07-24. Each component follows this repo's conventions (kustomize
`helmCharts` pulling the project-maintained upstream chart, pinned versions,
namespace manifest, ExternalSecrets instead of inline secrets).

**None of these are wired into `clusters/internal/values.yaml` — that is
intentional.** Nothing here is deployed. To adopt a stack, paste its
`values.yaml` snippet (below) into the cluster's `applications:` map and let
Argo CD sync it.

All components pass `make test` (yamllint, `kustomize build --enable-helm`,
kubeconform).

## Inventory

| Stack | Component | Upstream source | Version | Namespace | Suggested wave |
|---|---|---|---|---|---|
| Alerting (Alertmanager routing) | `components/alertmanager-config` | Raw manifests | n/a | `monitoring` | 15 |
| Logging (Loki + Alloy + log-gateway) | `components/loki-scalable` | https://grafana.github.io/helm-charts | 7.1.0 | `loki-scalable` | 11 |
| Logging (Loki + Alloy + log-gateway) | `components/alloy-logs` | https://grafana.github.io/helm-charts | 1.11.0 | `alloy-logs` | 13 |
| Logging (Loki + Alloy + log-gateway) | `components/log-gateway` | raw manifests | grafana/alloy:v1.18.0 | `log-gateway` | 15 |
| StackRox (RHACS parity) | `components/stackrox-central-services` | https://mirror.openshift.com/pub/rhacs/charts/ | 400.11.1 | `stackrox` | 20 |
| StackRox (RHACS parity) | `components/stackrox-secured-cluster-services` | https://mirror.openshift.com/pub/rhacs/charts/ | 400.11.1 | `stackrox` | 21 |
| Tekton Pipelines | `components/tekton-pipelines` | https://github.com/tektoncd/operator/releases/download/v0.80.0/release.… | v0.80.0 | `tekton-operator` | 15 |
| CloudNativePG + barman-cloud plugin | `components/cloudnative-pg-barman-plugin` | https://cloudnative-pg.github.io/charts | 0.7.0 | `cnpg-system` | 21 |
| Grafana (operator + dashboards) | `components/grafana-operator` | oci://ghcr.io/grafana/helm-charts/grafana-operator | 5.24.0 | `grafana` | 12 |
| NVIDIA GPU Operator | `components/nvidia-gpu-operator` | https://helm.ngc.nvidia.com/nvidia | v26.3.3 | `nvidia-gpu-operator` | 13 |
| Cluster API (+ autoscaler) | `components/cluster-api-operator` | https://kubernetes-sigs.github.io/cluster-api-operator | 0.28.0 | `capi-operator-system` | 10 |
| Cluster API (+ autoscaler) | `components/cluster-api-autoscaler` | https://kubernetes.github.io/autoscaler | 9.59.0 | `cluster-api-autoscaler-system` | 12 |
| Velero (OADP parity) | `components/velero` | https://vmware-tanzu.github.io/helm-charts | 12.1.0 | `velero` | 13 |

## Global prerequisites

- **ClusterSecretStores**: external-secrets on rk8s still has no `onepassword`
  ClusterSecretStore backend wired up (see README). Every ExternalSecret in
  these components stays degraded until the referenced stores exist
  (`onepassword-lab-external-api-keys`, `onepassword-lab-aap`, plus the
  per-stack stores each component's manifests reference).
- **Gotify**: the alerting default receiver targets
  `alertmanager-gotify-bridge.gotify.svc`, which does not exist on rk8s yet.
- **StackRox init bundle**: cluster registration secrets are generated at
  runtime by Central and cannot live in git.
- Per-stack activation notes and dropped-OpenShift-ism details are under each
  section below.

## Alerting (Alertmanager routing)

Ported the OCP alerting stack (igou-openshift/components/alertmanager-config) to a new INERT rk8s component components/alertmanager-config. The raw OpenShift alertmanager-main Secret was translated into a native prometheus-operator AlertmanagerConfig (monitoring.coreos.com/v1alpha1) named alertmanager-routing with FULL routing/receiver parity: same route tree (Watchdog/AlertmanagerReceiversNotConfigured/FailedToSendAlerts null-routes, severity critical/warning/info fan-out, info null-routed), same two inhibit_rules, same gotify webhook default receiver, and the two Slack chat.postMessage receivers targeting the SAME channels (#igoucloud-alerts-critical, #igoucloud-alerts-warning) via bot-token auth. Both ExternalSecrets were ported keeping identical 1Password item/property references and secretStoreRef names (onepassword-lab-external-api-keys for Slack, onepassword-lab-aap for EDA). The EDA route/receiver stays commented-out to match current OCP live state (secret staged). Slack api_url (a public endpoint, not a secret) is delivered via an ESO Merge template because AlertmanagerConfig slackConfig.apiURL must be a SecretKeySelector. No existing file (including kube-prometheus-stack) was modified. Renders cleanly and passes yamllint.

### `components/alertmanager-config`

- **Source**: Raw manifests (no chart): monitoring.coreos.com/v1alpha1 AlertmanagerConfig + two external-secrets.io/v1 ExternalSecrets. Ported from igou-openshift/components/alertmanager-config (raw alertmanager-main Secret). The AlertmanagerConfig CRD is provided by the existing kube-prometheus-stack component (prometheus-operator, includeCRDs).
- **Version**: n/a (no helm chart; AlertmanagerConfig CRD ships with kube-prometheus-stack 87.5.1 already pinned in that component)
- **Namespace**: monitoring
- **Suggested sync wave**: 15

Adoption snippet for `clusters/internal/values.yaml`:

```yaml
  alertmanager-config:
    annotations:
      argocd.argoproj.io/compare-options: IgnoreExtraneous
      # After kube-prometheus-stack (wave 10) which owns the monitoring
      # namespace, the Alertmanager workload, and the AlertmanagerConfig CRD
      # this component's CR and ExternalSecrets depend on. Also needs
      # external-secrets-operator (wave 0). ArgoCD retries cover residual gaps.
      argocd.argoproj.io/sync-wave: '15'
    destination:
      namespace: monitoring
    source:
      path: components/alertmanager-config
```

**Gaps / prerequisites:**

- ACTIVATION REQUIRES A kube-prometheus-stack VALUES CHANGE (not made — that component is off-limits). The AlertmanagerConfig is inert until the Alertmanager is pointed at it. Preferred (faithful) wiring is as the GLOBAL top-level config so the ported route tree + root `gotify` receiver + inhibit rules become the entire Alertmanager config. Add under alertmanager.alertmanagerSpec in components/kube-prometheus-stack/kustomization.yaml:
      alertmanager:
        alertmanagerSpec:
          alertmanagerConfiguration:
            name: alertmanager-routing
  Alternative (merged-child) mode instead keeps KPS's default root route/receiver and demotes this CR to a namespace-child route — to use it that way you must add BOTH `alertmanagerConfigSelector: {}` AND `alertmanagerConfigMatcherStrategy: {type: None}` (without type:None the operator injects a `namespace=monitoring` matcher and cluster-wide alerts never reach these routes). Global mode is recommended for exact parity.
- global.resolveTimeout (5m) cannot live in an AlertmanagerConfig — it is an Alertmanager global-only setting. 5m is already the Alertmanager default so this is a no-op; if it ever needs a non-default value, set alertmanager.alertmanagerSpec.alertmanagerConfiguration.global.resolveTimeout in kube-prometheus-stack values (KPS component, off-limits here).
- DROPPED: the OpenShift AlertRelabelConfig `drop-unsupported-hco-modification` (monitoring.openshift.io/v1). This API is OpenShift-only and has no vanilla prometheus-operator/AlertmanagerConfig analogue. Its target alert, UnsupportedHCOModification, is OpenShift-Virt/HCO-specific and does not exist on upstream KubeVirt (rk8s), so the drop is not meaningful here. If an equivalent Prometheus->Alertmanager alert-drop is ever needed on rk8s, it goes via prometheus.prometheusSpec.additionalAlertRelabelConfigs (a secret-backed relabel config in kube-prometheus-stack values), NOT via AlertmanagerConfig. Functionally moot anyway: severity=info is already null-routed.
- ClusterSecretStores are NOT wired on rk8s (see igou-kubernetes README: external-secrets has no ClusterSecretStore/onepassword backend yet). Both ExternalSecrets will stay degraded until the onepassword store(s) exist. The Slack ES references `onepassword-lab-external-api-keys` (already referenced by other rk8s components) and the EDA ES references `onepassword-lab-aap`, which does NOT yet appear anywhere in the rk8s repo (only -external-api-keys and -rk8s stores are referenced today) and must be created pointing at the AAP 1Password vault. Until the Slack secret materialises, both Slack receivers have no bot token and Slack delivery fails (Gotify leg still attempts).
- gotify-bridge DEPENDENCY MISSING ON rk8s: the ported webhook target http://alertmanager-gotify-bridge.gotify.svc:8080/gotify_webhook has no backing service in the rk8s repo (no gotify namespace/deployment/alertmanager-gotify-bridge exists). The default `gotify` receiver and the webhook leg of both severity receivers will fail delivery until a Gotify + alertmanager-gotify-bridge is deployed on rk8s (or the URL is repointed). Deploying Gotify is out of scope for this alerting port; flagged as a prerequisite for functional parity.
- EDA event-stream route/receiver intentionally NOT wired, matching the current OCP live state (the OCP alertmanager.yaml has the eda-github-issue route commented out; EDA pipeline not set up). The backing secret (alertmanager-eda-event-stream ExternalSecret) is staged so the route + receiver can be restored together in a single edit when the EDA pipeline exists on rk8s.
- Slack apiURL delivery detail: OCP embedded the literal `api_url: https://slack.com/api/chat.postMessage` inside the raw Secret. AlertmanagerConfig requires slackConfig.apiURL to be a SecretKeySelector, so the (public, non-secret) endpoint is stamped into the alertmanager-slack-bot-token Secret via an ESO target.template mergePolicy: Merge adding key `api_url`. No secret value is inlined in git — only the password comes from 1Password.

## Logging (Loki + Alloy + log-gateway)

Ported the full OCP central-logging stack to three NEW inert components in /workspace/igou-kubernetes (no existing file touched; git diff --stat empty). (1) components/loki-scalable: grafana/loki chart 7.1.0 in SimpleScalable mode against the same rustfs-cold S3 (truenas.igou.systems:20292, bucket `loki`), RF=1 single-replica-per-target (1x.demo parity), 31d compactor-enforced retention with per-stream overrides (syslog 92d, chatty-ns 7d), S3 creds via loki-s3 ExternalSecret (same 1P item loki-user-rustfs-cold / vault lab_s3, store onepassword-lab-s3) projected as env vars and expanded with -config.expand-env=true so no secret is inlined. (2) components/alloy-logs: grafana/alloy chart 1.11.0 DaemonSet collecting pod logs (/var/log/pods, node-scoped) + host journal (both journal paths), CRI parse + democratic-csi drop filter ported from the ClusterLogForwarder, writing to loki-gateway with external cluster=rk8s. (3) components/log-gateway: faithful raw-manifest port of the OCP syslog aggregator (Alloy v1.18.0) — RFC3164/5424 syslog + Loki-push listeners, MetalLB LoadBalancer VIP, ServiceMonitor, NetworkPolicy — with the write target swapped from the LokiStack tenant-RBAC gateway to the plain loki-gateway push API. All three pass `kustomize build --enable-helm` (exit 0) and yamllint; vendored chart caches removed so they are not committed.

### `components/loki-scalable`

- **Source**: https://grafana.github.io/helm-charts (chart: loki)
- **Version**: 7.1.0 (Loki appVersion 3.6.8)
- **Namespace**: loki-scalable
- **Suggested sync wave**: 11

Adoption snippet for `clusters/internal/values.yaml`:

```yaml
  loki-scalable:
    annotations:
      argocd.argoproj.io/compare-options: IgnoreExtraneous
      # SimpleScalable central log store. After external-secrets (wave 0,
      # for the loki-s3 creds) and democratic-csi (wave 7, iSCSI SC for
      # the write/backend PVCs). Same wave as the single-binary `loki`.
      argocd.argoproj.io/sync-wave: '11'
    destination:
      namespace: loki-scalable
    source:
      path: components/loki-scalable
```

### `components/alloy-logs`

- **Source**: https://grafana.github.io/helm-charts (chart: alloy)
- **Version**: 1.11.0 (Alloy appVersion v1.18.0)
- **Namespace**: alloy-logs
- **Suggested sync wave**: 13

Adoption snippet for `clusters/internal/values.yaml`:

```yaml
  alloy-logs:
    annotations:
      argocd.argoproj.io/compare-options: IgnoreExtraneous
      # Cluster log collector DaemonSet. After loki-scalable (wave 11, its
      # write target) and kube-prometheus-stack (wave 10, owns the
      # ServiceMonitor CRD this app emits).
      argocd.argoproj.io/sync-wave: '13'
    destination:
      namespace: alloy-logs
    source:
      path: components/alloy-logs
```

### `components/log-gateway`

- **Source**: raw manifests (faithful port; grafana/alloy v1.18.0 image, no project chart for this bespoke aggregator)
- **Version**: grafana/alloy:v1.18.0 (matches the alloy chart appVersion used by alloy-logs)
- **Namespace**: log-gateway
- **Suggested sync wave**: 15

Adoption snippet for `clusters/internal/values.yaml`:

```yaml
  log-gateway:
    annotations:
      argocd.argoproj.io/compare-options: IgnoreExtraneous
      # External-log ingest aggregator (syslog + loki-push). After
      # metallb (VIP), loki-scalable (wave 11, its write target) and
      # kube-prometheus-stack (ServiceMonitor CRD). Same wave as gateway.
      argocd.argoproj.io/sync-wave: '15'
    destination:
      namespace: log-gateway
    source:
      path: components/log-gateway
```

**Gaps / prerequisites:**

- ClusterSecretStore not wired on rk8s: the loki-s3 ExternalSecret references ClusterSecretStore `onepassword-lab-s3` (matching igou-openshift), but per the igou-kubernetes README external-secrets has NO ClusterSecretStore yet (the onepassword backend still needs wiring). Until then loki-scalable's loki-s3 secret stays unresolved and the Loki write/backend pods will not get S3 creds. The 1Password item `loki-user-rustfs-cold` (vault lab_s3, fields username/password) already exists (shared with ocp).
- Tenant model lost: the OCP LokiStack enforced application/infrastructure/audit tenants with OpenShift RBAC at the LokiStack gateway; vanilla grafana/loki has no equivalent. loki-scalable runs auth_enabled:false (single tenant) and ingest is unauthenticated in-cluster, fenced only at the network layer. The log-gateway's LokiStack infrastructure-writer ClusterRole/Binding (log-gateway-rbac.yaml) was therefore NOT ported. If multi-tenant isolation is wanted later, enable auth_enabled + X-Scope-OrgID headers on all writers, or front Loki with an authenticating proxy.
- Audit logs not collected: the ClusterLogForwarder collected a kubeAPI+openshiftAPI audit input (with a drop-audit-read-verbs filter). k3s does not ship an audit webhook/policy by default and there is no OpenShift audit source, so alloy-logs collects only pod logs + journal. The Loki audit-stream 14d retention override was consequently dropped. To achieve parity, enable the kube-apiserver audit policy on k3s and add a file-tail source for the audit log.
- AlertingRule not ported: the OCP central-logging LokiStack ruler evaluated a loki.grafana.com/v1 AlertingRule (RouterOS/TrueNAS silence, login failures, host OOM) delivered via the operator-wired platform Alertmanager. Vanilla loki-scalable has no ruler configured here. To port: enable the chart's `backend` ruler with rulerConfig.alertmanager_url pointing at kube-prometheus-stack's Alertmanager and mount the rules as a ConfigMap (LogQL expressions carry over verbatim; drop the tenantID). Left out to keep this component inert.
- VIP + DNS collision: syslog.igou.systems currently resolves to the LIVE OCP log-gateway VIP 10.10.150.16 (ocp owns the low half of the trusted-lan /24). The rk8s port pins a distinct high-half address 10.10.150.145 (metallb.io convention). Adopting the rk8s log-gateway means either cutting the syslog.igou.systems DNS static (rb5009, igou-inventory) over to .145 and repointing every device/host sender, or giving it a separate hostname. Both clusters cannot own the same VIP.
- Relationship to existing central-logging: rk8s CURRENTLY ships its logs OUT to the OCP LokiStack — the ansible-managed host alloy (igou-ansible roles/alloy) forwards journals to the OCP log-gateway, and any in-cluster rk8s alloy pushes there too (see MEMORY central-logging #382). This ported stack is the INVERSE/standalone option: it stands up a self-contained store ON rk8s. Adopting it is an either/or decision — run rk8s as its own log island, or keep shipping to OCP. Do not run both writers to two stores without deciding label/retention ownership. (The old single-binary `components/loki` has since been retired from the repo, and the live `components/alloy` is the ship-to-OCP collector — `components/alloy-logs` here is its standalone counterpart writing to `loki-scalable`.)
- Retention-stream label semantics differ: the ported retention_stream selectors use `{job="syslog"}` (set by log-gateway, matches) and `{namespace=~"democratic-csi|intel-device-plugins|nvidia-gpu-operator"}`. Those namespace names are OCP-specific; on rk8s the chatty namespaces may be named differently (or absent), so that 7d override may match nothing until the selector is retuned to rk8s namespaces. The alloy-logs collector emits `namespace` (not the OCP `kubernetes_namespace_name`), which is why the selector was rewritten to `namespace`.
- Journal read requires root: alloy-logs runs the DaemonSet as runAsUser 0 to read root-owned /var/log/pods and the host journal (no SCC on k3s to grant an arbitrary UID). If a PodSecurity `restricted` label is later applied to ns alloy-logs this will be denied; a dedicated exemption or a fsGroup/systemd-journal-group approach would be needed. Same root note does not apply to log-gateway (it drops ALL caps, non-privileged).
- OCP-only NetworkPolicy rule dropped: the source log-gateway NetworkPolicy allowed :3500 from ns `hermes` (an OCP KubeVirt VM on the pod network). No hermes namespace exists on rk8s, so that rule was omitted. If an in-cluster rk8s sender uses a pod-CIDR source IP (not matched by the RFC1918 ipBlock), add an equivalent namespaceSelector rule for it.
- Image digest pinning: the OCP log-gateway deployment pinned alloy by sha256 digest; this port pins the tag v1.18.0 only (the digest could not be verified offline for the port). Recommend re-adding an @sha256 digest pin before adoption for supply-chain parity.
- loki-scalable memcached tiers (chunksCache/resultsCache) are disabled to match the lab-scale single-binary component; if query volume grows, re-enable them — the chart defaults request multiple Gi of memory each, which is why they are off.

## StackRox (RHACS parity)

Ported the OCP RHACS/StackRox operator stack (igou-openshift/components/rhacs-operator) to two INERT, ready-to-adopt vanilla-Kubernetes components under igou-kubernetes/components/, using the project-maintained StackRox 4.11.1 helm charts (stackrox-central-services + stackrox-secured-cluster-services, chart 400.11.1 from mirror.openshift.com/pub/rhacs/charts — the working 4.x helm-repo distribution; charts.stackrox.io is frozen at 3.74 and the stackrox/helm-charts GitHub repo has no repo index). stackrox-central-services carries Central + Scanner v2 (Scanner V4 disabled), the declarative-config ConfigMap (auth provider + global-admins->Admin role mapping), all six cluster-apps policy-as-code SecurityPolicy CRs (reconciled by the config-controller Deployment the chart ships — no operator needed; the securitypolicies CRD is included via includeCRDs), a Central-DB PVC on freenas-iscsi-ssd-csi, homelab-sized requests, and an HTTPRoute exposing the UI on the shared trusted-lan gateway. stackrox-secured-cluster-services carries Sensor/Collector(CORE_BPF)/Admission-control with the three init-bundle TLS ExternalSecrets. Enforcement/remediation is OFF exactly as on OCP (verified in the rendered cluster-config: admissionControl.enforce=false -> enabled/enforceOnUpdates false, fail-open). OpenShift-only constructs (OLM Subscription/OperatorGroup, SCCs, Routes, PSPs, integrated OCP monitoring, truenas-w1 hostname pins, the OVN-K-specific NetworkPolicies) were translated or dropped. Both components render cleanly with kustomize build --enable-helm and pass yamllint; no existing repo file was modified (the values.yaml entries above are provided but NOT written into clusters/internal/values.yaml).

### `components/stackrox-central-services`

- **Source**: https://mirror.openshift.com/pub/rhacs/charts/ (chart stackrox-central-services) — the project's 4.x helm-repo distribution; charts.stackrox.io is frozen at 3.74 and stackrox/helm-charts GitHub ships no repo index
- **Version**: 400.11.1 (== appVersion 4.11.1, matches the OCP operator's 4.11.1)
- **Namespace**: stackrox
- **Suggested sync wave**: 20

Adoption snippet for `clusters/internal/values.yaml`:

```yaml
  stackrox-central-services:
    annotations:
      argocd.argoproj.io/compare-options: IgnoreExtraneous
      # After external-secrets (0), democratic-csi (7, owns the storageClass
      # the central-db PVC needs) and gateway (15, owns the trusted-lan
      # Gateway the central-httproute attaches to).
      argocd.argoproj.io/sync-wave: '20'
    destination:
      namespace: stackrox
    source:
      path: components/stackrox-central-services
```

### `components/stackrox-secured-cluster-services`

- **Source**: https://mirror.openshift.com/pub/rhacs/charts/ (chart stackrox-secured-cluster-services)
- **Version**: 400.11.1 (== appVersion 4.11.1)
- **Namespace**: stackrox
- **Suggested sync wave**: 21

Adoption snippet for `clusters/internal/values.yaml`:

```yaml
  stackrox-secured-cluster-services:
    annotations:
      argocd.argoproj.io/compare-options: IgnoreExtraneous
      # After stackrox-central-services (20): it owns the shared stackrox
      # namespace and Central must exist for Sensor to register.
      argocd.argoproj.io/sync-wave: '21'
    destination:
      namespace: stackrox
    source:
      path: components/stackrox-secured-cluster-services
```

**Gaps / prerequisites:**

- Init-bundle / cluster-registration flow (runtime, cannot live in git): Central mints the init bundle at runtime via `roxctl -e <central> central init-bundles generate rk8s --output-secrets`. Its three per-service TLS secrets (sensor-tls, collector-tls, admission-control-tls) are delivered by the ExternalSecrets in the secured component once the 1Password items stackrox-sensor-tls / stackrox-collector-tls / stackrox-admission-control-tls exist (field labels ca.pem / <svc>-cert.pem / <svc>-key.pem). Until then the secured-cluster pods stay degraded. Fallback: `kubectl apply -f cluster_init_bundle.yaml`, then let ESO adopt.
- Secured-cluster chart is NOT pure-GitOps: the chart requires the init-bundle CA at helm TEMPLATE time (chicken-and-egg), unlike the OCP operator path which reads the bundle Secret at runtime. components/stackrox-secured-cluster-services/values.yaml therefore embeds a clearly-labelled throwaway PLACEHOLDER CA (CN=PLACEHOLDER-REPLACE-WITH-INIT-BUNDLE-CA, public cert only, NO private key) purely so kustomize build renders. It MUST be replaced with the real init-bundle ca.pem at adoption or Sensor will not trust the real Central.
- ClusterSecretStore not wired on rk8s: the external-secrets component ships no ClusterSecretStore (see repo README). The three init-bundle ExternalSecrets reference `onepassword-lab-openshift` (name mirrors OCP) and sit in SecretSyncedError until both the store and the 1P items exist.
- Slack notifier is API-managed (same as OCP): declarative config supports only generic/splunk notifier types, not slack. The notifier `slack-igoucloud-alerts` (referenced by name in all six SecurityPolicy CRs) must be (re)created via `POST /v1/notifiers` using the 1P webhook `slack-webhook-igoucloud-alerts-warning`. Until it exists those notifier references are unresolved and violations do not post to #igoucloud-alerts-warning.
- Auth provider changed for k3s: OCP used an OpenShift-OAuth (`openshift:`) auth provider, which is invalid on k3s. The declarative config was ported as an `oidc:` provider with issuer=https://REPLACE-ME.rk8s.igou.systems and the group->role mapping (global-admins -> Admin) preserved. rk8s has no OIDC issuer defined yet — wiring one is an adoption prerequisite; until then only htpasswd break-glass (admin + the chart-generated central-htpasswd secret) works.
- UI exposure needs backend TLS + DNS: central-httproute.yaml attaches to the existing `*.rk8s.igou.systems` trusted-lan listener (no new listener needed) and the stackrox namespace carries the gateway-access/trusted-lan label. BUT the `central` Service serves HTTPS on 443, so NGINX Gateway Fabric needs a BackendTLSPolicy targeting it (NOT included) for the route to reach Central. Also an explicit DNS A record central.rk8s.igou.systems -> 10.10.150.129 must be added in igou-inventory (the *.rk8s wildcard was dropped there; each hostname needs its own record).
- Image pull secret / registry: chart images default to registry.redhat.io/advanced-cluster-security, which needs a pull secret this cluster has not wired. imagePullSecrets.allowNone: true lets the manifests render; before pulling, add a Red Hat pull secret OR repoint image.registry to quay.io/stackrox-io (community images).
- Node placement dropped: OCP pinned Central, Central-DB and Sensor to hostname truenas-w1 (its only non-tenant worker). That node does not exist on rk8s so all nodeSelectors were removed (pinning would make the pods unschedulable). Re-evaluate placement for the rk8s topology at adoption.
- OCP NetworkPolicies NOT ported: the source default-deny + allow-observed netpols encode OpenShift-specific selectors (openshift-dns, openshift-monitoring, policy-group.network.openshift.io/host-network for OVN-K SNAT, OCP pod/service CIDRs 10.128.0.0/14 + 172.30.0.0/16). They must be re-derived for rk8s (k3s CNI) if a default-deny posture is wanted. The stackrox charts do ship their own NetworkPolicies (5 in central, 3 in secured).
- SecurityPolicy scope namespaces are OCP-specific: the six CRs scope to the OCP cluster-apps app namespaces (ansible-automation-platform, comfyui, firecrawl, forgejo, gitea-mirror, gotify, hermes, jellyfin, llmkube-system, sands-of-time, searxng) and the Latest-tag policy excludes AAP automation-job/activation-job pods. Adjust these to the rk8s app namespaces at adoption.
- Built-in policy tuning is API-managed and NOT captured (same as OCP): namespace exclusions on the noisy built-ins (Docker CIS 4.1, Red Hat Package Manager in Image) for the AAP + GPU-operator namespaces must be re-applied via the policy API after install.
- Monitoring integration dropped: OCP used monitoring.openshift.enabled (integrated OCP platform monitoring). Disabled on k3s. To scrape Central/Sensor with the existing kube-prometheus-stack a ServiceMonitor / additionalScrapeConfig is needed — NOT included (follow-up).
- Helm-generated secret stability under GitOps: the central chart generates central-tls (incl. ca-key + jwt-key), central-db-password, central-htpasswd and scanner TLS at template time; under kustomize/ArgoCD these regenerate on every render unless pinned. For durable operation, supply stable values (central.jwtSigner, central.defaultTLS, central.adminPassword, central.db.password, scanner.dbPassword) sourced from new ExternalSecrets/1P items — NOT wired here.
- OLM constructs dropped: the RHACS operator Subscription, OperatorGroup and the platform.stackrox.io Central/SecuredCluster CRs were removed (no OLM on k3s) and replaced by the two helm charts. Policy-as-code still uses config.stackrox.io SecurityPolicy CRs, which ARE reconciled here by the config-controller Deployment the central chart ships (verified present in the render).
- kustomize+helm gotcha recorded in-repo: the secured chart's default values.yaml is entirely comments (zero real keys), which triggers a kustomize bug ('could not parse values file into rnode: EOF') whenever valuesInline is used. That component therefore uses valuesFile: values.yaml (passed straight to helm). Also note helm v4.2.2 / kustomize v5.8.1 in this environment; `roxctl` was NOT used (no cluster contact — authoring only).

## Tekton Pipelines

Ported the OpenShift Pipelines stack to a new inert rk8s component at components/tekton-pipelines/. It vendors the pinned upstream tektoncd/operator v0.80.0 Kubernetes release.yaml (no official Helm chart exists), plus a TektonConfig CR translated from the OCP one (targetNamespace openshift-pipelines -> tekton-pipelines; the OpenShift-only spec.platforms.openshift Pipelines-as-Code/Console block dropped), the tekton-ci-low PriorityClass, and the chains signing ExternalSecret (store swapped to the rk8s-native onepassword-lab-rk8s). The OLM Subscription is replaced by the vendored operator manifest. kustomize build --enable-helm renders cleanly (exit 0, 44 resources), yamllint passes, and git status shows only the new untracked directory. Files: /workspace/igou-kubernetes/components/tekton-pipelines/{kustomization.yaml,tektonconfig.yaml,tekton-ci-low-priorityclass.yaml,chains-signing-externalsecret.yaml}.

### `components/tekton-pipelines`

- **Source**: https://github.com/tektoncd/operator/releases/download/v0.80.0/release.yaml (upstream tektoncd/operator Kubernetes release manifest, vendored as a kustomize remote resource; NOT openshift-release.yaml). Tekton ships no project-maintained Helm chart, so vendoring the pinned release.yaml is the upstream-first approach.
- **Version**: v0.80.0 (tektoncd/operator latest stable, verified via GitHub releases API on 2026-07-24)
- **Namespace**: tekton-operator (operator + webhook, created by release.yaml) / tekton-pipelines (TektonConfig targetNamespace, created by the operator at reconcile)
- **Suggested sync wave**: 15

Adoption snippet for `clusters/internal/values.yaml`:

```yaml
  tekton-pipelines:
    annotations:
      argocd.argoproj.io/compare-options: IgnoreExtraneous
      # After external-secrets-operator (wave 0, provides the ClusterSecretStore
      # the chains signing ExternalSecret consumes). The vendored release.yaml
      # installs its own CRDs at wave 0, so the TektonConfig CR (internal wave
      # 11, SkipDryRunOnMissingResource) applies after them within the app.
      argocd.argoproj.io/sync-wave: '15'
    destination:
      namespace: tekton-operator
    source:
      path: components/tekton-pipelines
```

**Gaps / prerequisites:**

- OLM Subscription dropped: the OCP component installed the operator via an OLM Subscription (openshift-pipelines-operator-rh, redhat-operators). k3s has no OLM, so this is replaced by the vendored upstream release.yaml. No parity impact beyond source of the operator image (upstream ghcr.io/tektoncd vs Red Hat build).
- spec.platforms.openshift block dropped entirely from TektonConfig (OpenShift-only): this contained the Pipelines-as-Code enablement and PAC settings (application-name, secret-auto-create, remote-tasks, default-max-keep-runs, enable-cancel-in-progress-on-pull-requests/push) plus the four custom-console-* URLs pointing at the OpenShift Console. To get PAC on rk8s you must configure it under the vanilla operator's own PAC component/config (not the openshift platform field) and drop the Console URLs. Not ported.
- ClusterSecretStore not wired up on rk8s (per README): external-secrets has no functioning onepassword store until igou-ansible bootstrap-gitops seeds the Connect token. Until then the chains signing ExternalSecret stays degraded (SkipDryRunOnMissingResource keeps it from blocking sync).
- Vault-scoping gap for the chains signing secret: the tekton-chains-signing 1Password item lived in the lab_openshift vault via the OCP onepassword-lab-openshift store, which does not exist on rk8s. I pointed the ExternalSecret at the rk8s-native onepassword-lab-rk8s store (scoped to the lab_rk8s vault). To adopt, either copy the tekton-chains-signing item into lab_rk8s, or add a new ClusterSecretStore scoped to lab_openshift in components/external-secrets-operator/ (that is an existing-component change I did NOT make).
- Pipelines-as-Code tenant not ported: clusters/ocp/pac-tenants/values.yaml defines a PaC tenant (igou-ansible) via a pac-tenant Helm chart that builds ansible execution environments, pushes to Quay, wires Forgejo webhooks, injects RH Automation Hub Galaxy tokens, and adds NetworkPolicy egress. It depends on PAC (dropped above), OCP ImageStreams, and the pac-tenant chart which does not exist in igou-kubernetes. If CI pipelines are wanted on rk8s this is a separate follow-up (port the pac-tenant chart + a working ClusterSecretStore for the ci-* / quay / automationhub items).
- No standalone Pipeline/Task/Trigger CRs exist in igou-openshift outside the operator config: the actual pipeline definitions live in tenant repos' .tekton/ directories consumed by PaC at trigger time, not in this GitOps repo. Nothing further to port.
- Dashboard UI not exposed: profile 'all' installs tekton-dashboard (Service tekton-dashboard in tekton-pipelines, port 9097) which the operator creates at reconcile. The OCP source exposed no Route it owned (it used the OpenShift Console), so no HTTPRoute was ported. Optional follow-up: add an HTTPRoute on the shared nginx-gateway (follow components/gateway pattern) if the dashboard should be reachable.
- tekton-pipelines namespace is created by the operator, not shipped as a manifest (matching the kubevirt component). The signing-secrets ExternalSecret targets that namespace and relies on internal sync-wave ordering (TektonConfig wave 11 before ExternalSecret wave 12) plus SkipDryRunOnMissingResource until the operator creates it.
- Renovate: the release.yaml is pinned via a GitHub-release URL in kustomization resources (v0.80.0). The repo's standard Renovate yaml/kustomize managers will not bump a raw release URL; add a regex custom manager (like the OCP repo uses for democratic-csi image pins) or bump the version manually on operator releases.

## CloudNativePG + barman-cloud plugin

The rk8s repo already runs the cloudnative-pg operator (components/cloudnative-pg, chart 0.29.0, namespace cnpg-system, live in values.yaml), so the ported operator component was dropped as redundant — only the missing half is delivered here: components/cloudnative-pg-barman-plugin installs the project-maintained plugin-barman-cloud chart 0.7.0 (app v0.13.0) into cnpg-system, the live operator's namespace (required for operator gRPC/mTLS discovery). The chart provisions its own self-signed cert-manager Issuer + server/client Certificates; the server cert uses the relative dnsName 'barman-cloud' so it is mTLS-safe. Unlike OCP (which vendored the raw v0.12.0 release manifest and stripped runAsUser via a JSON patch for the restricted-v2 SCC), k3s has no SCC so the chart's default securityContext applies as-is. No database Cluster CRs were created; the plugin component's README carries a fully commented ObjectStore + Cluster + ScheduledBackup + ExternalSecret example showing the rustfs S3 backup pattern and the serverName restore-key convention (RESTORE key = committed plugin serverName, bump to -r<date> after any DR). Both components validated with kustomize build --enable-helm; only new untracked directories appear in git status; no existing file was modified.

### `components/cloudnative-pg-barman-plugin`

- **Source**: https://cloudnative-pg.github.io/charts (chart: plugin-barman-cloud)
- **Version**: chart 0.7.0 (app v0.13.0)
- **Namespace**: cnpg-system (the live cloudnative-pg operator's namespace)
- **Suggested sync wave**: 21

Adoption snippet for `clusters/internal/values.yaml`:

```yaml
  cloudnative-pg-barman-plugin:
    annotations:
      argocd.argoproj.io/compare-options: IgnoreExtraneous
      argocd.argoproj.io/sync-wave: '21'
    destination:
      namespace: cnpg-system
    source:
      path: components/cloudnative-pg-barman-plugin
```

**Gaps / prerequisites:**

- Secrets/ClusterSecretStore not wired: the rk8s external-secrets install has NO ClusterSecretStore (per igou-kubernetes README). The example CNPG backup ExternalSecret (onepassword-lab-s3 store, item cnpg-s3-backup) will stay Pending until the onepassword store is configured. No secret values were inlined.
- Version delta vs OCP: OCP runs the barman plugin at raw-manifest v0.12.0; this port uses the project-maintained chart 0.7.0 => app v0.13.0 (same v0.x line, one minor ahead). Chosen per the 'always favor the project-maintained chart' + 'pin latest stable' rules. To exactly match OCP, pin chart 0.6.0 (app v0.12.0) instead.
- Operator version delta: OCP OLM channel stable-v1 was on app 1.29.1; this port pins operator chart 0.29.0 => app 1.30.0 (latest stable). If lockstep with OCP is desired, pin chart 0.28.3 (app 1.29.1).
- To adopt: add the two values_snippet entries to clusters/internal/values.yaml (NOT done, per instructions). Suggested waves 20/21 (after kube-prometheus-stack wave 10 so the PodMonitor is picked up, and after cert-manager wave 5 which the plugin's Issuer/Certificates depend on). These are new waves beyond the current max in that file.
- OCP NetworkPolicies dropped: the OCP clusters/ocp/cloudnative-pg overlay adds default-deny + allow-observed NetworkPolicies around the operator namespace. Not ported (rk8s has no equivalent netpol baseline component yet). Add later if network isolation parity is wanted.
- Storage class parity for future Clusters: OCP forgejo/etc Clusters use freenas-nvmeof-ssd-csi and pin to the control-plane node to dodge a democratic-csi Multi-Attach bug on RWO PVC migration. The README example uses freenas-iscsi-ssd-csi per this task's persistence convention; revisit storageClass + node affinity when a real rk8s Cluster is authored.
- No grafanaDashboard: the operator chart can also emit a CNPG Grafana dashboard (monitoring.grafanaDashboard.create). Left disabled to match OCP (which shipped only a ServiceMonitor + metrics Service). Enable later for dashboard parity once a Grafana operator owns dashboards on rk8s.
- rustfs S3 endpoint/CA: the example points destinationPath at s3://cnpg-backups/<name> via endpointURL https://truenas.igou.systems:20292 (OCP convention). If the rk8s-facing rustfs endpoint presents a private-CA cert, a per-namespace CA-bundle secret + ObjectStore.configuration.endpointCA is required (noted commented in README).

## Grafana (operator + dashboards)

Ported the Grafana stack from igou-openshift to a new INERT components/grafana-operator in igou-kubernetes, using the project-maintained grafana-operator Helm chart (OCI, v5.24.0, includeCRDs) plus the full set of ported CRs. Created 6 authored manifests (kustomization.yaml, grafana-namespace.yaml, grafana-grafana.yaml, grafana-prometheus-datasource.yaml, grafana-loki-datasource.yaml, grafana-httproute.yaml), copied all 55 GrafanaDashboard CRs and 43 vendored dashboard JSON files. Translations from OCP: (1) Thanos Querier datasource -> in-cluster kube-prometheus-stack Prometheus (http://kube-prometheus-stack-prometheus.monitoring.svc:9090, isDefault, no bearer/TLS); (2) three OCP LokiStack tenant datasources -> single rk8s Loki (http://loki-gateway.loki-scalable.svc, the ported loki-scalable component); every dashboard datasourceName rewritten accordingly (thanos-querier->prometheus, loki-{infrastructure,application,network}->loki); (3) OCP reencrypt Route + oauth-proxy sidecar/SAR/service-serving-cert -> plain HTTPRoute on the shared trusted-lan Gateway at grafana.rk8s.igou.systems (auth dropped); (4) PVC storageClass nvmeof -> freenas-iscsi-ssd-csi. Dropped OCP-only resources (OperatorGroup/Subscription, SA token + cluster-monitoring-view/auth-delegator/loki-tenant RBAC, OVN NetworkPolicies). No live cluster access; local rendering only; no existing files modified.

### `components/grafana-operator`

- **Source**: oci://ghcr.io/grafana/helm-charts/grafana-operator (project-maintained grafana-operator Helm chart) + ported Grafana/GrafanaDatasource/GrafanaDashboard CRs and vendored dashboard JSON from igou-openshift/components/grafana
- **Version**: 5.24.0 (appVersion v5.24.0; latest v5 verified against ghcr.io OCI registry via helm show chart)
- **Namespace**: grafana
- **Suggested sync wave**: 12

Adoption snippet for `clusters/internal/values.yaml`:

```yaml
  grafana-operator:
    annotations:
      argocd.argoproj.io/compare-options: IgnoreExtraneous
      # After kube-prometheus-stack (wave 10, owns the monitoring ns +
      # prometheus Service the default datasource targets), loki (wave 11,
      # owns loki-gateway), and gateway (wave 15, owns the trusted-lan
      # Gateway the HTTPRoute attaches to). ArgoCD retries cover residual
      # ordering; the operator/CRDs and CRs are internally wave-ordered.
      argocd.argoproj.io/sync-wave: '16'
    destination:
      namespace: grafana
    source:
      path: components/grafana-operator
```

**Gaps / prerequisites:**

- AUTHENTICATION GAP (important): OCP fronted Grafana with an oauth-proxy sidecar performing OpenShift SSO + SAR authorization. Vanilla k3s has none of that. The ported instance falls back to Grafana's OWN local login form (disable_login_form: false); the operator auto-generates admin creds into Secret grafana-admin-credentials. The HTTPRoute exposes Grafana on the trusted LAN with NO auth proxy in front — only the local login form. If SSO is desired later, front it with oauth2-proxy or a Gateway auth filter. auth.proxy/X-Forwarded-User trust and auto_assign_org_role: Admin were removed.
- ClusterSecretStore NOT wired up: per igou-kubernetes README, external-secrets has no ClusterSecretStore (onepassword store + backend still need wiring). This component intentionally consumes NO ExternalSecret — the OCP oauth-cookie Password generator + ExternalSecret were dropped along with the oauth-proxy. Nothing here depends on a secret store, so it is not blocked, but note the store is still absent fleet-wide.
- OCP-only datasource backends have no rk8s equivalent: the OCP loki-application (user-namespace pod logs) and loki-network (netobserv eBPF flow store) tenants do not exist on rk8s. Their dashboard references were collapsed onto the single tenantless rk8s Loki. Those boards (and the vendored lokistack/ocp/logging/netobserv dashboards) will render but return no data until equivalent log streams exist on rk8s.
- Dashboards were ported 1:1 including OCP-specific ones (rk8s-* federation boards assume UWM federation + exported_namespace relabeling; logging lokistack operator-console boards; ocp-application/infrastructure-logs; netobserv-traffic). They are inert/empty on rk8s but kept so the set stays complete and ready to adopt. Prune later if undesired.
- NetworkPolicies DROPPED: the source default-deny + allow-observed policies use OVN-Kubernetes/OpenShift-specific selectors (policy-group.network.openshift.io/host-network, openshift-* namespace names, node-CIDR ipBlocks). They do not translate to k3s. No NetworkPolicy was authored — port fresh from rk8s NetObserv/flow analysis if network isolation for the grafana namespace is wanted.
- DNS prerequisite: rk8s has no *.rk8s wildcard (igou-inventory#132). An EXPLICIT A record grafana.rk8s.igou.systems -> 10.10.150.129 (trusted-lan-gateway VIP) must be added in igou-inventory before the HTTPRoute is reachable.
- grafana-operator chart CRDs are bundled in-chart (includeCRDs: true) alongside the operator Deployment in one Argo app — same self-contained pattern as kube-prometheus-stack/loki. No separate CRD app needed.
- Sync-wave: the component is internally ordered (Grafana wave 11, datasources 11, HTTPRoute 12, dashboards 12) matching the source. The suggested app-of-apps wave is 16 (after kube-prometheus-stack=10, loki=11, gateway=15). Not written into clusters/internal/values.yaml per instructions — see values_snippet.
- Not adopted: no entry was added to clusters/internal/values.yaml and the component is not referenced by any cluster — this is authoring-only. Adopt by pasting the values_snippet.
- Two orphan dashboard JSON files carried over verbatim from source and left unreferenced (matching source state): dashboards/lab-power.json (no CR / not in configMapGenerator upstream) is present but unused; the source's dashboards/logging/generate.py build script was removed as non-manifest content.

## NVIDIA GPU Operator

Ported the NVIDIA GPU Operator (+NFD) from the OpenShift OLM stack to a single INERT vanilla-k8s component at components/nvidia-gpu-operator, using the project-maintained NGC gpu-operator Helm chart v26.3.3 via kustomize helmCharts. Design decision: NFD comes from the chart's BUNDLED nfd (nfd.enabled:true, upstream default) rather than a separate node-feature-discovery component, collapsing the OCP split into one chart. The OCP ClusterPolicy intent is translated into chart valuesInline (the chart renders its own ClusterPolicy): driver.enabled with nvidiaDriverCRD.enabled:true + deployDefaultCR:false to carry the two per-node driver pools, usePrecompiled:false for the standard driver-container flow (NOT the OCP driver-toolkit/RHCOS path), time-slicing config ported verbatim (4 replicas per nvidia.com/gpu via devicePlugin.config default:any), dcgmExporter serviceMonitor enabled, cdi/dcgm/gfd/migManager(all-disabled)/vgpuDeviceManager/vfioManager/sandboxDevicePlugin/nodeStatusExporter enabled to match, daemonsets tolerating the casval workload=burst taint, and the standard upstream-documented k3s toolkit env (CONTAINERD_CONFIG/SOCKET/RUNTIME_CLASS/SET_AS_DEFAULT). The two NVIDIADriver CRs (pascal-580 for p330/Quadro P620, burst-595 for casval) are raw manifests with node-selector semantics kept verbatim. No ExternalSecret is needed — the source stack references no secret (vGPU/NLS licensing disabled). Renders and lints clean; no existing repo file touched.

### `components/nvidia-gpu-operator`

- **Source**: https://helm.ngc.nvidia.com/nvidia (gpu-operator, project-maintained NGC chart)
- **Version**: v26.3.3 (chart == appVersion; matches the OCP CSV v26.3.x branch)
- **Namespace**: nvidia-gpu-operator
- **Suggested sync wave**: 13

Adoption snippet for `clusters/internal/values.yaml`:

```yaml
  nvidia-gpu-operator:
    annotations:
      argocd.argoproj.io/compare-options: IgnoreExtraneous
      # After kube-prometheus-stack (wave 10) so the dcgm-exporter
      # ServiceMonitor's CRD exists; bundled NFD ships with the chart so no
      # separate node-feature-discovery dependency.
      argocd.argoproj.io/sync-wave: '13'
    destination:
      namespace: nvidia-gpu-operator
    source:
      path: components/nvidia-gpu-operator
```

**Gaps / prerequisites:**

- NO GPU HARDWARE ON rk8s: rk8s workers are ARM64 RK3588 Armbian boards (opi5pro-01, rock-5a-01, orange-pi-5-01, orange-pi-5-max-01) on a cm3588-nas-01 k3s control plane (per igou-inventory group_vars/rk8s.yml + inventory.yaml). The GPU nodes p330 (Quadro P620) and casval (burst) are OpenShift bare-metal x86 workers, NOT rk8s members. This component is therefore inert on the current rk8s node set; the NVIDIADriver hostname selectors (p330.igou.systems / casval.igou.systems) are OCP hostnames carried over verbatim so the manifest stays a faithful ready-to-adopt port and have no live effect until matching x86 GPU nodes are added to rk8s.
- DRIVER INSTALL STRATEGY DIFFERS from OCP: dropped operator.use_ocp_driver_toolkit:true and the RHCOS precompiled flow; set driver.usePrecompiled:false (standard NVIDIA driver-container). NVIDIA driver containers target x86_64 Ubuntu/RHEL/CentOS kernels and do NOT support ARM64 Rockchip SBCs (no discrete NVIDIA GPU), so even if adopted the driver DaemonSet only ever schedules onto the (non-rk8s) x86 GPU nodes named in the CRs. On adoption, confirm the driver image tag matches the actual OS+kernel of those x86 nodes (the rk8s ARM boards run Armbian/Debian-trixie and are irrelevant to the driver).
- BUNDLED NFD DOES NOT PORT THE OCP NFD WORKER TUNING: the OCP openshift-nfd NodeFeatureDiscovery set core.sleepInterval:300s (to stop the worker throttling past its 200m CPU limit / accumulating restarts) and a pci sources deviceClassWhitelist (0200 network, 03 display, 12 accelerators) + deviceLabelFields (class, vendor). The gpu-operator chart's bundled NFD (nfd.enabled) does not expose these knobs. If that tuning is required, replace bundled NFD with a separate node-feature-discovery component (NFD project chart) and set gpu-operator nfd.enabled:false. Not ported here (chose bundled/upstream-default per the preferred option).
- rk8s ClusterSecretStore is not wired up yet (see igou-kubernetes README: external-secrets has no ClusterSecretStore; the onepassword store/backend still need configuring). This does NOT block the GPU stack because the source OCP ClusterPolicy references no secret (licensingConfig.secretName empty, vGPU/vgpuManager disabled) — no ExternalSecret was created. If NLS vGPU licensing is ever enabled, it would need a gridd.conf/client-token secret sourced via an ExternalSecret against the onepassword ClusterSecretStore, which must be wired up first.
- OpenShift-only objects DROPPED in translation (recorded, not ported): OLM Subscription (gpu-operator-certified, channel v26.3) and OperatorGroup — replaced by the Helm chart; the second OLM Subscription/OperatorGroup + NodeFeatureDiscovery (nfd.openshift.io/v1) from openshift-nfd — replaced by bundled NFD; namespace label openshift.io/cluster-monitoring:true (OCP UWM-specific) — dropped, kube-prometheus-stack selects ServiceMonitors cluster-wide; ClusterPolicy operator.defaultRuntime:crio — dropped (k3s uses containerd, handled via toolkit env).
- INERT OCP RBAC RULE IN CHART OUTPUT: the chart's operator/validator ClusterRole includes a rule for apiGroups security.openshift.io / resources securitycontextconstraints. This is a chart-authored RBAC rule (not a SecurityContextConstraints object) and is a harmless no-op on vanilla k8s where that resource type is absent. Left as-is rather than JSON6902-patching the chart output, to keep the component minimal.
- NO Route/HTTPRoute needed: the gpu-operator exposes no external UI/API. dcgm-exporter is scraped in-cluster via a ServiceMonitor (dcgmExporter.serviceMonitor.enabled:true) picked up by kube-prometheus-stack, so nothing attaches to the shared nginx-gateway-fabric gateway. Confirm on adoption that the ServiceMonitor in namespace nvidia-gpu-operator is selected (kube-prometheus-stack uses serviceMonitorSelectorNilUsesHelmValues:false = cluster-wide, so it should be).
- NOT wired into clusters/internal/values.yaml (per task hard rules — existing files untouched). Suggested sync-wave 13 (after kube-prometheus-stack wave 10 so the ServiceMonitor CRD exists). The values_snippet in the component output is ready to paste under applications: if/when the stack is adopted.

## Cluster API (+ autoscaler)

Ported the CAPI stack from igou-openshift to igou-kubernetes as two new inert components, both rendering cleanly via `kustomize build --enable-helm` and passing yamllint. (1) components/cluster-api-operator uses the kubernetes-sigs cluster-api-operator helm chart (bumped 0.27.0 -> latest stable 0.28.0), mirroring the exact three providers OCP declares in providers.yaml: CoreProvider cluster-api v1.12.7 (MachineTaintPropagation gate), InfrastructureProvider metal3 v1.12.4, IPAMProvider metal3 v1.12.4, plus the three namespaces and the workload-cluster-access RBAC. (2) components/cluster-api-autoscaler replaces the raw OCP Deployment with the project-maintained cluster-autoscaler chart 9.59.0 set to cloudProvider=clusterapi/incluster-incluster, reproducing every OCP flag (enforce-node-group-min-size, scale-down timings, expander=least-waste, etc.), the control-plane nodeSelector/tolerations, resources, and hardened securityContext, and adding the infra-provider read grant the chart omits. No OpenShift APIs appear in either rendered output. Chart versions verified against the live repo index.yaml files. No existing files were modified; only the two new untracked component directories were created (other untracked dirs in git status belong to parallel agents and were left untouched). The kustomize-generated charts/ cache dirs were removed to match the rk8s convention of not vendoring charts.

### `components/cluster-api-operator`

- **Source**: https://kubernetes-sigs.github.io/cluster-api-operator (kubernetes-sigs cluster-api-operator helm chart)
- **Version**: chart 0.28.0 (appVersion 0.28.0); providers CoreProvider cluster-api v1.12.7, InfrastructureProvider metal3 v1.12.4, IPAMProvider metal3 v1.12.4
- **Namespace**: capi-operator-system
- **Suggested sync wave**: 10

Adoption snippet for `clusters/internal/values.yaml`:

```yaml
  cluster-api-operator:
    annotations:
      argocd.argoproj.io/compare-options: IgnoreExtraneous
      argocd.argoproj.io/sync-wave: '10'
    destination:
      namespace: capi-operator-system
    source:
      path: components/cluster-api-operator
```

### `components/cluster-api-autoscaler`

- **Source**: https://kubernetes.github.io/autoscaler (kubernetes cluster-autoscaler helm chart, cloudProvider=clusterapi)
- **Version**: chart 9.59.0 (appVersion 1.35.0, image v1.35.0)
- **Namespace**: cluster-api-autoscaler-system
- **Suggested sync wave**: 12

Adoption snippet for `clusters/internal/values.yaml`:

```yaml
  cluster-api-autoscaler:
    annotations:
      argocd.argoproj.io/compare-options: IgnoreExtraneous
      argocd.argoproj.io/sync-wave: '12'
    destination:
      namespace: cluster-api-autoscaler-system
    source:
      path: components/cluster-api-autoscaler
```

**Gaps / prerequisites:**

- DROPPED (OpenShift-only): the three nonroot-v2 SCC RoleBindings (capi-manager/capm3-manager/ipam-manager). Vanilla k8s has no SCCs. Replaced their intent with explicit PodSecurity Admission namespace labels (capi-system/capm3-system = baseline; capi-operator-system = privileged). If a hardened rk8s cluster later enforces a stricter default, verify the CAPI/CAPM3 controllers still admit under baseline.
- DROPPED (OpenShift-only): machine-approver-capi-rbac.yaml (bound the openshift-cluster-machine-approver SA to read cluster.x-k8s.io/machines for kubelet CSR approval). Vanilla k8s / k3s has NO machine-approver. CAPI-provisioned worker node kubelet serving/client CSRs will NOT be auto-approved — an adopter must run a CSR approver (e.g. the cluster-api kubeadm bootstrap flow auto-approves client CSRs via the bootstrap token, but kubelet-serving CSRs still need `--rotate-server-certificates` handling or a manual/controller approver). Flag before first CAPI node join.
- DROPPED (OpenShift-only): the two large RFC 6902 CoreProvider patches that rewrote ipaddressclaims/ipaddresses.ipam.cluster.x-k8s.io to byte-match the OCP release-image CRDs for CVO<->capi-operator SSA shared ownership. No CVO on vanilla k8s, so capi-operator is sole owner and the patches are unnecessary (and would pin an OCP-specific schema). If both metal3 IPAM and cluster-api IPAM CRDs are ever installed and fight, revisit.
- SECRETS / ClusterSecretStore: neither source component consumed any ExternalSecret, so none were authored. Separately, the rk8s onepassword ClusterSecretStore is still not wired up (see igou-kubernetes README) — anything that later needs a workload-cluster kubeconfig Secret would depend on it, but CAPI here is configured incluster-incluster so no external kubeconfig Secret is required.
- PLACEHOLDER namespace/cluster identifiers require adoption: capi-workload-cluster-access-rbac.yaml binds the `default` SA in namespace `capi-cluster`, and the autoscaler's autoDiscovery is clusterName=rk8s,namespace=capi-cluster. OCP used openshift-cluster-api / ocp-hb42r. No CAPI Cluster or MachineDeployments exist in igou-kubernetes yet (there is no clusters/*/cluster-api path). An adopter must create that namespace + Cluster/MachineDeployment set and align all three references (RBAC subject ns, autoDiscovery.namespace, autoDiscovery.clusterName).
- No Route/HTTPRoute needed: neither the operator nor the autoscaler exposes a UI/API Route in the OCP source, so nothing to attach to the shared nginx-gateway-fabric gateway.
- Autoscaler image tag pinned to chart default v1.35.0 (appVersion 1.35.0). The OCP raw deployment tracked the management cluster's k8s minor (was v1.34.0). Bump image.tag to match the rk8s/k3s server's k8s minor on cluster upgrade to avoid a version skew warning.
- PROVIDER SET mirrors OCP exactly (Core + Metal3 Infra + Metal3 IPAM); no standalone BootstrapProvider/ControlPlaneProvider CRs are declared, matching OCP. If the intended CAPI workflow needs kubeadm bootstrap/control-plane bundles beyond what the core provider release ships, add BootstrapProvider/ControlPlaneProvider CRs.
- ADOPTION (not applied per task): these components are inert. To activate, add the two `applications:` entries from values_snippet to clusters/internal/values.yaml (waves 10 and 12, matching OCP ordering, after cert-manager which the operator's webhooks depend on).
- OPTIONAL DOC follow-up per /workspace/CLAUDE.md: consider adding a short page under /workspace/igou-docs describing the ported CAPI stack and the machine-approver/CSR gap — not done here since this is authoring-only.

## Velero (OADP parity)

Ported the OCP cluster-backup capability (redhat-oadp-operator) to a new INERT components/velero using the project-maintained VMware-Tanzu Velero chart (pinned 12.1.0 / Velero 1.18.1, verified against the live index.yaml). OADP is Red Hat's Velero distro, so this is a faithful upstream stand-in. KEY DISCOVERY: igou-openshift installed the OADP operator but NEVER defined a DataProtectionApplication, BackupStorageLocation, or Schedule (confirmed by the 2026-07-03 DR post-mortem: 'redhat-oadp-operator component exists in-repo but is not enabled'). There was therefore no DPA/BSL/schedule to translate 1:1 — the component is a sensible cold-storage parity baseline derived from the repo's existing rustfs S3 pattern (loki/netobserv). Parity choices: BSL -> COLD RustFS S3 (truenas.igou.systems:20292, bucket velero, s3ForcePathStyle) matching the loki/netobserv ExternalSecret pattern; credentials via ExternalSecret (secretStoreRef onepassword-lab-s3, 1P item velero-user-rustfs-cold fields username/password) templated into Velero's `cloud` AWS-INI secret key; aws plugin v1.14.2 (tracks Velero 1.18) + kubevirt-velero-plugin v0.9.0 initContainers (cluster runs KubeVirt); CSI enabled via --features=EnableCSI (democratic-csi freenas-iscsi-ssd-csi exposes CSI snapshots, so no native VolumeSnapshotLocation); node-agent OFF (OADP had no DPA, so never enabled it); schedules {} (none existed). Component: velero-namespace.yaml + velero-s3-externalsecret.yaml + kustomization.yaml (helmCharts, includeCRDs). Renders clean, yamllint clean, no OpenShift APIs, no existing file modified. Not written into clusters/internal/values.yaml (values_snippet provided for later adoption).

### `components/velero`

- **Source**: https://vmware-tanzu.github.io/helm-charts (velero) + plugin images velero/velero-plugin-for-aws:v1.14.2, quay.io/kubevirt/kubevirt-velero-plugin:v0.9.0
- **Version**: chart 12.1.0 (appVersion Velero 1.18.1)
- **Namespace**: velero
- **Suggested sync wave**: 13

Adoption snippet for `clusters/internal/values.yaml`:

```yaml
  velero:
    annotations:
      argocd.argoproj.io/compare-options: IgnoreExtraneous
      # After external-secrets-operator (wave 0, for the S3 credential) and
      # democratic-csi (wave 7, whose CSI driver+snapshots the CSI backups
      # target). No hard dep on kube-prometheus/loki; sits after them.
      argocd.argoproj.io/sync-wave: '13'
    destination:
      namespace: velero
    source:
      path: components/velero
```

**Gaps / prerequisites:**

- NO DPA TO PORT: igou-openshift's redhat-oadp-operator installs the OLM operator only — no DataProtectionApplication, BackupStorageLocation, VolumeSnapshotLocation, or Schedule CR exists anywhere in components/, applications/, or clusters/ (grep-verified; corroborated by docs/post-mortems/2026-07-03-ocp-disaster-recovery.md which states OADP is 'not enabled in clusters/ocp/values.yaml'). This velero component is a NEW parity baseline, not a 1:1 translation. Plugin set (aws+csi+kubevirt) and endpoint/bucket were inferred from the repo's rustfs S3 convention and the DR post-mortem's stated intent ('scheduled backups of namespaces, app CRs, and PV data to RustFS/S3'), not from any committed OADP config.
- NO SCHEDULES PORTED: because OADP defined none. schedules is left {} in the chart values. Adopting real backup cadence requires adding schedule entries (or velero.io/v1 Schedule manifests) with an agreed cron + TTL/retention.
- ClusterSecretStore not wired on rk8s: the velero-s3-credentials ExternalSecret uses secretStoreRef onepassword-lab-s3 (the store igou-openshift's rustfs ExternalSecrets use). Per igou-kubernetes/README.md NO ClusterSecretStore is configured on rk8s yet (only onepassword-lab-rk8s, onepassword-lab-external-api-keys, onepassword-connect-token are referenced elsewhere, and even those depend on an unwired onepassword backend). The ExternalSecret — and thus the BSL credential — stays degraded until the onepassword-lab-s3 store + backend are provisioned on rk8s.
- 1Password item + RustFS IAM user do not exist yet: need item `velero-user-rustfs-cold` (vault lab_s3, fields username/password), a `velero` IAM user on the COLD RustFS instance (igou-inventory host_vars/rustfs-cold.yml applied via AAP rustfs_state_converge), and a `velero` bucket created on that instance. Mirrors the existing loki-user-rustfs-cold / netobserv-user-rustfs-cold setup.
- node-agent OFF = no PV DATA in S3 yet: deployNodeAgent is false for OADP parity (OADP had no DPA, hence no node-agent). With CSI enabled, volume backups are CSI VolumeSnapshots that remain in-cluster on the democratic-csi/TrueNAS backend — they are NOT copied into the rustfs bucket. To achieve the DR post-mortem's stated 'PV data' backups to S3, set deployNodeAgent: true and enable CSI snapshot data movement (data mover); this also adds a DaemonSet + node-agent RBAC.
- CSI snapshot prerequisites missing on k3s: CSI backups need (a) the external-snapshotter CRDs (VolumeSnapshot/Class/Content) and snapshot-controller, which k3s does not bundle by default, and (b) a VolumeSnapshotClass for the org.democratic-csi.iscsi driver labelled `velero.io/csi-volumesnapshot-class: "true"`. The democratic-csi component in this repo (clusters/internal/democratic-csi) ships no VolumeSnapshotClass. Without these, CSI snapshotting no-ops.
- No HTTPRoute authored: Velero exposes no user-facing UI/API — it is driven by kubectl/the velero CLI and a metrics port (:8085). igou-openshift's OADP defined no Route, so there is nothing to port to the shared nginx-gateway-fabric Gateway. (If Prometheus scraping of Velero metrics is wanted, add a ServiceMonitor — the chart supports metrics.serviceMonitor.enabled but kube-prometheus-stack here already selects ServiceMonitors cluster-wide.)
- suggested_sync_wave 13 is a recommendation only and is NOT written into clusters/internal/values.yaml (per the do-not-modify-existing-files rule). Use the provided values_snippet if/when adopting. Wave 13 sequences after external-secrets (0) and democratic-csi (7); adjust if the CSI VolumeSnapshotClass/snapshot-controller is delivered by a later-wave component.
- Chart renders a one-shot Helm-hook Job `velero-upgrade-crds` (+ its ServiceAccount/ClusterRole); ArgoCD renders it as an ordinary resource. Harmless (idempotent CRD apply) but worth an argocd.argoproj.io/hook or Replace sync-option if it causes churn on resync.

