"""Readiness must reject missing, unhealthy, or misaddressed nodes."""
import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location('lab', Path(__file__).resolve().parents[1] / 'scripts/lab.py')
lab = importlib.util.module_from_spec(spec)
spec.loader.exec_module(lab)

class ReadinessTests(unittest.TestCase):
    def setUp(self):
        self.expected = {'server': {'name': 'k3s-server', 'ip': '192.168.100.10'}}
        self.actual = {'items': [{'metadata': {'name': 'k3s-server'}, 'status': {
            'conditions': [{'type': 'Ready', 'status': 'True'}],
            'addresses': [{'type': 'InternalIP', 'address': '192.168.100.10'}]}}]}

    def test_ready(self):
        self.assertEqual(lab.readiness_errors(self.expected, self.actual), [])

    def test_missing_node(self):
        self.assertTrue(lab.readiness_errors(self.expected, {'items': []}))

    def test_not_ready(self):
        self.actual['items'][0]['status']['conditions'][0]['status'] = 'False'
        self.assertTrue(lab.readiness_errors(self.expected, self.actual))

    def test_wrong_ip(self):
        self.actual['items'][0]['status']['addresses'][0]['address'] = '192.168.100.99'
        self.assertTrue(lab.readiness_errors(self.expected, self.actual))

if __name__ == '__main__':
    unittest.main()
