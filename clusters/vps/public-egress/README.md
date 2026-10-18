# Public service exit node

The Tailscale operator manages one exit node named `vps-public-egress`, tagged
with the existing `tag:vps-public-service`. It gives public OpenShift workloads
the same outbound public IP as their inbound VPS endpoint.

Approve this device's exit-node routes explicitly and permit only the existing
`tag:ocp-public-service` sources to use it on the required application ports.
No new tag, tailnet suffix, public listener, or subnet advertisement is needed.
The paired OpenShift gateway selects the device by its short hostname.

The NetworkPolicy isolates this Connector using its dedicated pod label. It
permits DNS and the local state API, public TCP 80/443 and 27000–27100, and
public UDP for Tailscale transport and Steam. The tailnet grant and OpenShift
forwarding firewall restrict forwarded UDP to 27000–27100. Private destination
addresses are excluded from internet access; the operator proxy's existing
credential model remains an infrastructure trust boundary.

The node runs in the existing `tailscale` namespace and is managed by the
dedicated VPS Argo CD. Its Application registration is in the paired
`igou-openshift/clusters/ocp/vps/values.yaml` change. Render with
`kustomize build clusters/vps/public-egress`.

Operational preparation, rollout checks, and rollback are documented in
`igou-docs/networking/Public Service Sharing with AAP.md`. A successful UDP ping
alone does not establish that Steam authentication works.
