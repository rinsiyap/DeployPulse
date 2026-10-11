import json
import re


RULES = [
    ("CRITICAL", ["data loss", "security breach", "production down", "service unavailable"]),
    ("HIGH", ["timeout", "database unavailable", "authentication failure", "error rate"]),
    ("MEDIUM", ["slow", "latency", "failed request", "retry"]),
]


def lambda_handler(event, context):
    body = event.get("body") or event

    if isinstance(body, str):
        try:
            body = json.loads(body)
        except json.JSONDecodeError:
            return response(400, {"error": "Invalid JSON request body."})

    description = str(body.get("description", "")).strip()
    if not description:
        return response(400, {"error": "A description is required."})

    text = description.lower()
    severity = "LOW"
    matched_rules = []

    for level, keywords in RULES:
        matches = [word for word in keywords if re.search(r"\b" + re.escape(word) + r"\b", text)]
        if matches:
            severity = level
            matched_rules = matches
            break

    return response(200, {
        "description": description[:1000],
        "severity": severity,
        "matched_rules": matched_rules,
        "classifier": "rule-based"
    })


def response(status_code, body):
    return {
        "statusCode": status_code,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps(body)
    }
