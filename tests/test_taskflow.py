import importlib.util
import json
import unittest
from pathlib import Path
from unittest.mock import MagicMock, patch


ROOT = Path(__file__).resolve().parents[1]


def load_module(name, relative_path):
    spec = importlib.util.spec_from_file_location(name, ROOT / relative_path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


classifier = load_module(
    "incident_classifier",
    "app/incident_classifier/lambda_function.py"
)


class IncidentClassifierTests(unittest.TestCase):
    def classify(self, description):
        event = {"body": json.dumps({"description": description})}
        result = classifier.lambda_handler(event, None)
        return result["statusCode"], json.loads(result["body"])

    def test_critical_incident(self):
        status, body = self.classify("Production down after release")
        self.assertEqual(status, 200)
        self.assertEqual(body["severity"], "CRITICAL")

    def test_high_incident(self):
        status, body = self.classify("Database unavailable")
        self.assertEqual(status, 200)
        self.assertEqual(body["severity"], "HIGH")

    def test_medium_incident(self):
        status, body = self.classify("High latency detected")
        self.assertEqual(status, 200)
        self.assertEqual(body["severity"], "MEDIUM")

    def test_low_incident(self):
        status, body = self.classify("Minor cosmetic issue")
        self.assertEqual(status, 200)
        self.assertEqual(body["severity"], "LOW")

    def test_empty_description(self):
        status, body = self.classify("")
        self.assertEqual(status, 400)
        self.assertIn("error", body)


if __name__ == "__main__":
    unittest.main()
