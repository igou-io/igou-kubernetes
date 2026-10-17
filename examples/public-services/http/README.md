# HTTP sharing

This folder pairs with `igou-openshift/test-workloads/public-services/http/`.
The native `HTTPRoute` attaches to `nginx-gateway/public` and selects the bridge
Service in `tailscale`. The bridge selects the Tailscale egress proxy for
`ocp-public-web-test` in `public-services`, targeting
`ocp-public-web-test.weasel-alioth.ts.net` on TCP 8080.

After installing the prerequisites in `../README.md` and rolling out both
sides, check from outside the tailnet:

```bash
curl --fail https://web-test.igou.io/
```

Expect `public-services web test`. Check the route's `Accepted` and `ResolvedRefs`
conditions. Public forwarding remains unverified.
