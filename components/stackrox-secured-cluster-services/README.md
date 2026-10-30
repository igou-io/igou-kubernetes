# RHACS secured cluster

Connects rk8s to the existing ACS 4.11.6 Central on OCP. The official
`rhacs-operator` Helm chart manages the `rk8s` SecuredCluster; the historical
directory name is retained. `rhacs-secured-cluster` in
`clusters/internal/values.yaml` adopts this component at sync wave 20.

Sensor connects to Central's existing passthrough route on TCP 443. Both
local scanners are disabled: OCP's Scanner V4 indexes and matches image
vulnerabilities. There is no local Central, scanner database, PVC, or ingress.
The separate `stackrox-central-services` component remains inactive and
must not be adopted alongside this configuration.

The component owns the privileged `stackrox` namespace, its Operator, and
SecuredCluster resource. Admission enforcement is Disabled. Collector uses
CORE_BPF on every node; BTF and ARM64 image availability were checked before
adoption. Runtime compatibility still requires validation on the actual
Armbian/k3s kernels.

ExternalSecrets use `onepassword-lab-rk8s`:

- `rhacs-registry`: `lab_rk8s/rhacs-redhat-registry`, field
  `dockerconfigjson`, supplies registry.redhat.io pull credentials to the
  Operator and agents.
- `cluster-registration-secret`: `lab_rk8s/rhacs-cluster-registration`, field
  `crs`, supplies Central's dedicated registration artifact. Central and the
  Operator then own the generated service TLS material; do not restore the
  old sensor/collector/admission TLS ExternalSecrets.

Namespaces precede ExternalSecrets (waves -3/-2); the Operator chart is
wave 0 and SecuredCluster wave 1. The parent Application uses server-side
apply for the Operator's large CRDs. Both backing items must exist before
syncing, and Central must complete its initial vulnerability import before
claiming scan coverage.

With five nodes, configured requests are approximately 1010m CPU / 5070Mi
memory including the Operator, Sensor, admission controller, and assuming
three containers per Collector pod. This is a reservation, not measured usage;
extra image-processing load is on OCP. Existing kubelet/cAdvisor monitoring
in rk8s supplies resource measurements.

Bootstrap, approval/rollout status, and verification are maintained in
`igou-docs/security/RHACS Secured Cluster Bootstrap.md`, section
**rk8s enrollment**.
