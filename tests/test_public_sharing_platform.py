"""Check the public listener pool and the runtime identity's namespace boundary."""
from pathlib import Path
import unittest

import yaml

ROOT = Path(__file__).resolve().parents[1]


class PublicSharingPlatformTests(unittest.TestCase):
    def test_public_pool_has_matching_host_ports_and_protocol_routes(self):
        gateway = yaml.safe_load((ROOT / 'clusters/vps/gateway-api/public-gateway.yaml').read_text())
        config = yaml.safe_load((ROOT / 'clusters/vps/nginx-gateway-fabric/kustomization.yaml').read_text())
        mappings = config['helmCharts'][0]['valuesInline']['nginx']['container']['hostPorts']
        for listener in gateway['spec']['listeners']:
            if listener['protocol'] not in ('TCP', 'UDP'):
                continue
            self.assertIn({'port': listener['port'], 'containerPort': listener['port']}, mappings)
            self.assertEqual(listener['name'], f"{listener['protocol'].lower()}-{listener['port']}")
            self.assertEqual(listener['allowedRoutes']['kinds'][0]['kind'], listener['protocol'] + 'Route')
        public = {(l['protocol'], l['port']) for l in gateway['spec']['listeners'] if l['protocol'] in ('TCP', 'UDP')}
        self.assertEqual(public, {('TCP', p) for p in range(27010, 27018)} | {('UDP', p) for p in range(27018, 27026)})

    def test_runtime_identity_cannot_read_secrets_or_edit_gateway(self):
        for path in (ROOT / 'clusters/vps/public-sharing').glob('*-role.yaml'):
            role = yaml.safe_load(path.read_text())
            self.assertIn(role['metadata']['namespace'], ('public-services', 'tailscale', 'nginx-gateway'))
            for rule in role['rules']:
                self.assertFalse({'secrets', 'pods', 'namespaces', '*'} & set(rule['resources']))
                if 'gateways' in rule['resources']:
                    self.assertEqual(rule['verbs'], ['get'])
                    self.assertEqual(rule['resourceNames'], ['public'])
