import json
import os
import uuid
from datetime import datetime, timezone

import boto3

TABLE_NAME = os.environ.get("TASKS_TABLE", "deploypulse-tasks")
table = boto3.resource("dynamodb").Table(TABLE_NAME)


def lambda_handler(event, context):
    method = event.get("requestContext", {}).get("http", {}).get("method", "GET")

    if method == "GET":
        response = table.scan(Limit=50)
        return reply(200, {"tasks": response.get("Items", [])})

    if method == "POST":
        try:
            body = event.get("body") or "{}"
            if isinstance(body, str):
                body = json.loads(body)

            title = str(body.get("title", "")).strip()
            if not title:
                return reply(400, {"error": "A task title is required."})

            task = {
                "task_id": str(uuid.uuid4()),
                "title": title[:200],
                "status": "OPEN",
                "created_at": datetime.now(timezone.utc).isoformat()
            }
            table.put_item(Item=task)
            return reply(201, {"task": task})
        except (json.JSONDecodeError, TypeError, ValueError):
            return reply(400, {"error": "Invalid JSON request body."})

    return reply(405, {"error": "Method not allowed."})


def reply(status_code, body):
    return {
        "statusCode": status_code,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps(body, default=str)
    }
