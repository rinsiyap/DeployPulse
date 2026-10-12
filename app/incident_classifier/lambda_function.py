
import json
import logging
import os
import re
import uuid
from datetime import datetime, timezone

import boto3


# Configure logging for AWS CloudWatch Logs
logger = logging.getLogger()
logger.setLevel(logging.INFO)


# Incident severity classification rules.
# More severe rules are evaluated first.
RULES = [
    (
        "CRITICAL",
        [
            "data loss",
            "security breach",
            "production down",
            "service unavailable",
        ],
    ),
    (
        "HIGH",
        [
            "timeout",
            "database unavailable",
            "authentication failure",
            "error rate",
            "threshold crossed",
            "lambda reported",
        ],
    ),
    (
        "MEDIUM",
        [
            "slow",
            "latency",
            "failed request",
            "retry",
        ],
    ),
]


# Environment variables configured by Terraform
INCIDENTS_TABLE = os.environ.get(
    "INCIDENTS_TABLE",
    "deploypulse-incidents",
)
SNS_TOPIC_ARN = os.environ.get("SNS_TOPIC_ARN", "")


# AWS service clients and resources
dynamodb = boto3.resource("dynamodb")
incidents_table = dynamodb.Table(INCIDENTS_TABLE)
sns = boto3.client("sns")


def classify(description):
    """Classify an incident description using keyword-based rules."""
    text = str(description).lower()

    for level, keywords in RULES:
        matches = [
            word
            for word in keywords
            if re.search(r"\b" + re.escape(word) + r"\b", text)
        ]

        if matches:
            return level, matches

    return "LOW", []


def lambda_handler(event, context):
    """Handle HTTP API requests and SQS incident events."""

    # Validate the incoming event.
    if not isinstance(event, dict):
        return response(
            400,
            {"error": "A JSON object is required."},
        )

    # Process incidents delivered through the SQS event source mapping.
    records = event.get("Records")

    if isinstance(records, list) and records:
        if (
            isinstance(records[0], dict)
            and records[0].get("eventSource") == "aws:sqs"
        ):
            return process_sqs_records(records)

    # Preserve the existing HTTP API behavior.
    body = event.get("body")
    if body is None:
        body = event

    if isinstance(body, str):
        try:
            body = json.loads(body)
        except json.JSONDecodeError:
            return response(
                400,
                {"error": "Invalid JSON request body."},
            )

    if not isinstance(body, dict):
        return response(
            400,
            {"error": "A JSON object is required."},
        )

    description = str(body.get("description", "")).strip()

    if not description:
        return response(
            400,
            {"error": "A description is required."},
        )

    severity, matched_rules = classify(description)

    logger.info(
        "Incident classification completed: severity=%s",
        severity,
    )

    return response(
        200,
        {
            "description": description[:1000],
            "severity": severity,
            "matched_rules": matched_rules,
            "classifier": "rule-based",
        },
    )


def process_sqs_records(records):
    """Store incidents and publish notifications for SQS messages."""
    failures = []

    for record in records:
        message_id = record.get("messageId", "unknown")

        try:
            message = json.loads(record["body"])

            if not isinstance(message, dict):
                raise ValueError("SQS message body must contain a JSON object.")

            detail = message.get("detail") or {}
            if not isinstance(detail, dict):
                raise ValueError("Event detail must be a JSON object.")

            alarm = detail.get(
                "alarmName",
                "Unknown CloudWatch alarm",
            )

            state = detail.get("state") or {}
            if not isinstance(state, dict):
                raise ValueError("Alarm state must be a JSON object.")

            reason = state.get(
                "reason",
                "No alarm reason provided",
            )

            description = f"{alarm}: {reason}"
            severity, matched_rules = classify(description)

            incident = {
                "incident_id": str(uuid.uuid4()),
                "alarm_name": str(alarm),
                "description": description[:1000],
                "severity": severity,
                "matched_rules": matched_rules,
                "status": "OPEN",
                "created_at": datetime.now(timezone.utc).isoformat(),
            }

            # Store the incident in DynamoDB.
            incidents_table.put_item(Item=incident)

            logger.info(
                "Incident stored: incident_id=%s severity=%s alarm=%s",
                incident["incident_id"],
                severity,
                incident["alarm_name"],
            )

            # Publish the notification through SNS.
            if SNS_TOPIC_ARN:
                sns.publish(
                    TopicArn=SNS_TOPIC_ARN,
                    Subject=f"[{severity}] DeployPulse incident",
                    Message=json.dumps(incident, indent=2),
                )

                logger.info(
                    "SNS notification published for incident_id=%s",
                    incident["incident_id"],
                )
            else:
                logger.warning(
                    "SNS_TOPIC_ARN is empty; no email notification sent."
                )

        except Exception:
            # Log the traceback and request retry of this SQS message.
            logger.exception(
                "Failed to process incident SQS message_id=%s",
                message_id,
            )

            failures.append(
                {"itemIdentifier": message_id}
            )

    # Retry only failed SQS messages.
    return {"batchItemFailures": failures}


def response(status_code, body):
    """Format an HTTP API response as JSON."""
    return {
        "statusCode": status_code,
        "headers": {
            "Content-Type": "application/json",
        },
        "body": json.dumps(body, default=str),
    }