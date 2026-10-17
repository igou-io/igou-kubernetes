# Public sharing boundary

This component owns the AAP sharing identity, permanent public-proxy network
policy, and native admission constraints. It grants no Secret reads or Pod
creation. Admission applies to `public-services/aap-public-share` and protects
other Services, policies, grants and routes from that credential. New forwarding
objects must use stamped share names, owner and expiry, public tags, the
`public-services` ProxyClass, the approved Gateway listeners and their own bridge.
Specs and owner/share IDs cannot change after creation; only expiry is renewed.
The tailnet domain in admission must be reviewed when moving to another tailnet.

The Gateway component separately limits its controller and data plane traffic.
Public proxy transport permits public TCP 443, UDP 3478/41641, DNS and fixed API
endpoints; private peer paths may require DERP. API and node exceptions mean
NetworkPolicy is not a host or credential-isolation boundary. The operator still
uses privileged proxies with a shared, broad state-Secret identity. Separating
public proxy state from management credentials requires a supported proxy
architecture change; `ProxyClass` cannot set service accounts or namespaces in
the installed versions. Do not deploy a second competing operator as a shortcut.

Pause share creation and drain existing temporary shares before coordinated
rollout. Existing old-format shares can be removed by their owner or cleanup
before admission is enabled. New policy rejects attempts to extend a legacy
share that lacks the required ProxyClass or selector. Install the ProxyClass,
permanent policies and admission along with the matching Ansible renderer.
Then sync the inventory's credential type, scoped credential, execution
environment and templates. Resume sharing after HTTP, raw TCP and UDP response
checks and negative API/network checks in an authorized rollout.

The legacy service-account-token Secret is no longer provisioned. GitOps has
pruning disabled: explicitly delete its existing copy during an authorized
rollout after confirming bounded TokenRequest credentials work. Do not delete
the active 1Password credential. Keep the permanent baseline outside cleanup.
