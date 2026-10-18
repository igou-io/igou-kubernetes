# UDP sharing

This folder pairs with `igou-openshift/test-workloads/public-services/udp/`.
The native `UDPRoute` attaches to `nginx-gateway/public` and selects the bridge
Service in `tailscale`. The bridge selects the Tailscale egress proxy for
`ocp-udp-echo` in `public-services`, targeting
`ocp-public-udp-echo.example.ts.net` on UDP 9000.

After installing the prerequisites in `../README.md` and rolling out both
sides, check from outside the tailnet:

```bash
printf 'echo hello\n' | nc -u -w 3 udp-test.igou.io 27018
```

Expect `hello`. Check the route's `Accepted` and `ResolvedRefs`
conditions. Public forwarding remains unverified.
