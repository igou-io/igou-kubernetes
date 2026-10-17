from __future__ import annotations

import copy
from pathlib import Path
import subprocess
import tempfile
import unittest

import yaml


CHART = Path(__file__).resolve().parents[1] / ".helm/charts/tailscale-public-services"


class PublicServicesTests(unittest.TestCase):
    def setUp(self) -> None:
        self.values = yaml.safe_load((CHART / "examples/web-test-values.yaml").read_text())

    def render(self, values: dict) -> subprocess.CompletedProcess:
        with tempfile.NamedTemporaryFile(mode="w", suffix=".yaml") as config:
            yaml.safe_dump(values, config)
            config.flush()
            return subprocess.run(
                ["helm", "template", "test", str(CHART), "-f", config.name],
                capture_output=True, text=True, check=False,
            )

    def test_defaults_publish_nothing(self) -> None:
        result = self.render({})
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(list(yaml.safe_load_all(result.stdout)), [])

    def test_routes_resolve_to_matching_bridge_ports_and_named_grants(self) -> None:
        for filename, kind in [("web-test-values.yaml", "HTTPRoute"),
                               ("web-test-tcp-values.yaml", "TCPRoute"),
                               ("udp-values.yaml", "UDPRoute")]:
            with self.subTest(example=filename):
                values = yaml.safe_load((CHART / "examples" / filename).read_text())
                result = self.render(values)
                self.assertEqual(result.returncode, 0, result.stderr)
                objects = list(yaml.safe_load_all(result.stdout))
                bridge = next(o for o in objects if o["kind"] == "Service" and o["spec"]["type"] == "ClusterIP")
                self.assertEqual(bridge["metadata"]["namespace"], "tailscale")
                self.assertEqual(bridge["spec"]["selector"]["tailscale.com/parent-resource-ns"], "public-services")
                self.assertEqual(bridge["spec"]["selector"]["tailscale.com/parent-resource-type"], "svc")
                grant = next(o for o in objects if o["kind"] == "ReferenceGrant")
                self.assertEqual(grant["spec"]["to"], [{"group": "", "kind": "Service", "name": bridge["metadata"]["name"]}])
                self.assertEqual({p["kind"] for p in grant["spec"]["from"]}, {kind})
                route = next(o for o in objects if o["kind"].endswith("Route"))
                self.assertEqual(route["kind"], kind)
                ref = route["spec"]["rules"][0]["backendRefs"][0]
                self.assertEqual(ref["name"], bridge["metadata"]["name"])
                self.assertEqual(ref["namespace"], bridge["metadata"]["namespace"])
                protocol = "UDP" if kind == "UDPRoute" else "TCP"
                self.assertIn((ref["port"], protocol), {(p["port"], p["protocol"]) for p in bridge["spec"]["ports"]})

    def test_http_requires_hostname_and_uses_http_service_port(self) -> None:
        result = self.render(self.values)
        service = next(o for o in yaml.safe_load_all(result.stdout) if o["kind"] == "Service")
        self.assertEqual(service["spec"]["ports"][0]["name"], "http-web")
        del self.values["services"][0]["ports"][0]["hostnames"]
        self.assertNotEqual(self.render(self.values).returncode, 0)

    def test_rejects_ambiguous_listeners_and_backend_ports(self) -> None:
        ports = self.values["services"][0]["ports"]
        ports.append({"name": "tcp", "port": 8081, "protocol": "TCP", "listener": "tcp-27010"})
        for index, field, value in [(0, "listener", "tcp-27010"), (1, "port", 8080)]:
            with self.subTest(field=field):
                values = copy.deepcopy(self.values)
                values["services"][0]["ports"][index][field] = value
                self.assertNotEqual(self.render(values).returncode, 0)
        duplicate = copy.deepcopy(ports[1])
        duplicate["name"] = "another"
        duplicate["listener"] = "other"
        ports.append(duplicate)
        self.assertIn("duplicate backend port", self.render(self.values).stderr)

    def test_rejects_non_tailnet_targets_and_management_tags(self) -> None:
        for values in [
            {"services": [{"name": "api", "tailnetFQDN": "api.example.com", "ports": []}]},
            {"proxyTag": "tag:vps"},
        ]:
            self.assertNotEqual(self.render(values).returncode, 0)

    def test_rejects_route_name_collisions_between_services(self) -> None:
        self.values["services"] = [
            {
                "name": "test-one", "tailnetFQDN": "one.example.ts.net",
                "ports": [{"name": "two", "port": 27015, "protocol": "TCP", "listener": "one"}],
            },
            {
                "name": "test", "tailnetFQDN": "two.example.ts.net",
                "ports": [{"name": "one-two", "port": 27016, "protocol": "TCP", "listener": "two"}],
            },
        ]
        self.assertIn("duplicate route name", self.render(self.values).stderr)
