# TCP sharing

This folder pairs with `igou-openshift/test-workloads/public-services/tcp/`.
The native `TCPRoute` attaches to `nginx-gateway/public` and selects the bridge
Service in `tailscale`. The bridge selects the Tailscale egress proxy for
`ocp-tcp-hostname` in `public-services`, targeting
`ocp-public-tcp-hostname.weasel-alioth.ts.net` on TCP 9000.

After installing the prerequisites in `../README.md` and rolling out both
sides, check from outside the tailnet:

```bash
nc -w 3 tcp-test.igou.io 27010 < /dev/null
```

Expect the answering pod's hostname. Check the route's `Accepted` and `ResolvedRefs`
conditions. Public forwarding remains unverified.
