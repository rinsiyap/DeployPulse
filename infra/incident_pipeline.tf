
# Incident records
resource "aws_dynamodb_table" "incidents" {
  name         = "deploypulse-incidents"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "incident_id"

  attribute {
    name = "incident_id"
    type = "S"
  }

  tags = {
    Project     = "DeployPulse"
    Environment = "dev"
  }
}

# Dead-letter queue for failed incident processing
resource "aws_sqs_queue" "incident_dlq" {
  name                      = "deploypulse-incident-dlq"
  message_retention_seconds = 1209600

  tags = {
    Project = "DeployPulse"
  }
}

# Queue for CloudWatch incident events
resource "aws_sqs_queue" "incident_events" {
  name                       = "deploypulse-incident-events"
  visibility_timeout_seconds = 60
  message_retention_seconds  = 345600

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.incident_dlq.arn
    maxReceiveCount     = 3
  })

  tags = {
    Project = "DeployPulse"
  }
}

# SNS topic for incident notifications
resource "aws_sns_topic" "incidents" {
  name = "deploypulse-incident-notifications"

  tags = {
    Project = "DeployPulse"
  }
}

# Optional email subscription
resource "aws_sns_topic_subscription" "incident_email" {
  count     = var.incident_notification_email == "" ? 0 : 1
  topic_arn = aws_sns_topic.incidents.arn
  protocol  = "email"
  endpoint  = var.incident_notification_email
}

# CloudWatch alarm for TaskFlow Lambda errors
resource "aws_cloudwatch_metric_alarm" "taskflow_errors" {
  alarm_name          = "deploypulse-taskflow-errors"
  alarm_description   = "TaskFlow Lambda reported one or more errors"
  namespace           = "AWS/Lambda"
  metric_name         = "Errors"
  statistic           = "Sum"
  period              = 60
  evaluation_periods  = 1
  threshold           = 0
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"

  dimensions = {
    FunctionName = aws_lambda_function.taskflow.function_name
  }

  tags = {
    Project = "DeployPulse"
  }
}

# Route alarm state changes to SQS
resource "aws_cloudwatch_event_rule" "lambda_errors" {
  name        = "deploypulse-lambda-error-events"
  description = "Route TaskFlow alarm state changes to the incident queue"

  event_pattern = jsonencode({
    source        = ["aws.cloudwatch"]
    "detail-type" = ["CloudWatch Alarm State Change"]
    resources     = [aws_cloudwatch_metric_alarm.taskflow_errors.arn]
    detail = {
      state = {
        value = ["ALARM"]
      }
    }
  })

  tags = {
    Project = "DeployPulse"
  }
}

# Deliver matching alarm events to the incident queue
resource "aws_cloudwatch_event_target" "incident_queue" {
  rule      = aws_cloudwatch_event_rule.lambda_errors.name
  target_id = "DeployPulseIncidentQueue"
  arn       = aws_sqs_queue.incident_events.arn

  depends_on = [
    aws_sqs_queue_policy.allow_eventbridge
  ]
}

# Allow EventBridge to send alarm events to SQS
resource "aws_sqs_queue_policy" "allow_eventbridge" {
  queue_url = aws_sqs_queue.incident_events.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowEventBridgeSendMessage"
        Effect = "Allow"
        Principal = {
          Service = "events.amazonaws.com"
        }
        Action   = "sqs:SendMessage"
        Resource = aws_sqs_queue.incident_events.arn
        Condition = {
          ArnEquals = {
            "aws:SourceArn" = aws_cloudwatch_event_rule.lambda_errors.arn
          }
        }
      }
    ]
  })
}

# Permissions for the classifier to process incidents
resource "aws_iam_role_policy" "classifier_incidents" {
  name = "deploypulse-classifier-incident-processing-policy"
  role = aws_iam_role.classifier.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "sqs:ReceiveMessage",
          "sqs:DeleteMessage",
          "sqs:GetQueueAttributes"
        ]
        Resource = aws_sqs_queue.incident_events.arn
      },
      {
        Effect   = "Allow"
        Action   = ["dynamodb:PutItem"]
        Resource = aws_dynamodb_table.incidents.arn
      },
      {
        Effect   = "Allow"
        Action   = ["sns:Publish"]
        Resource = aws_sns_topic.incidents.arn
      }
    ]
  })
}

# Trigger the classifier when an SQS message arrives
resource "aws_lambda_event_source_mapping" "incident_queue" {
  event_source_arn = aws_sqs_queue.incident_events.arn
  function_name    = aws_lambda_function.classifier.arn
  batch_size       = 1
  enabled          = true

  function_response_types = ["ReportBatchItemFailures"]

  depends_on = [
    aws_iam_role_policy.classifier_incidents
  ]
}