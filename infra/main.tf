resource "aws_dynamodb_table" "tasks" {
  name         = "deploypulse-tasks"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "task_id"

  attribute {
    name = "task_id"
    type = "S"
  }

  point_in_time_recovery {
    enabled = false
  }

  tags = {
    Project     = "DeployPulse"
    Environment = "dev"
  }
}

resource "aws_iam_role" "taskflow" {
  name = "deploypulse-taskflow-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "taskflow" {
  name = "deploypulse-taskflow-policy"
  role = aws_iam_role.taskflow.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "${aws_cloudwatch_log_group.taskflow.arn}:*"
      },
      {
        Effect = "Allow"
        Action = [
          "dynamodb:Scan",
          "dynamodb:PutItem"
        ]
        Resource = aws_dynamodb_table.tasks.arn
      }
    ]
  })
}

resource "aws_iam_role" "classifier" {
  name = "deploypulse-classifier-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "classifier_logs" {
  name = "deploypulse-classifier-logs-policy"
  role = aws_iam_role.classifier.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ]
      Resource = "${aws_cloudwatch_log_group.classifier.arn}:*"
    }]
  })
}

resource "aws_cloudwatch_log_group" "taskflow" {
  name              = "/aws/lambda/deploypulse-taskflow"
  retention_in_days = 14
}

resource "aws_cloudwatch_log_group" "classifier" {
  name              = "/aws/lambda/deploypulse-incident-classifier"
  retention_in_days = 14
}

resource "aws_lambda_function" "taskflow" {
  function_name    = "deploypulse-taskflow"
  role             = aws_iam_role.taskflow.arn
  runtime          = "python3.13"
  handler          = "lambda_function.lambda_handler"
  filename         = "${path.module}/../build/taskflow.zip"
  source_code_hash = filebase64sha256("${path.module}/../build/taskflow.zip")
  timeout          = 10
  memory_size      = 128

  environment {
    variables = {
      TASKS_TABLE = aws_dynamodb_table.tasks.name
    }
  }

  depends_on = [aws_iam_role_policy.taskflow]
}

resource "aws_lambda_function" "classifier" {
  function_name    = "deploypulse-incident-classifier"
  role             = aws_iam_role.classifier.arn
  runtime          = "python3.13"
  handler          = "lambda_function.lambda_handler"
  filename         = "${path.module}/../build/incident_classifier.zip"
  source_code_hash = filebase64sha256("${path.module}/../build/incident_classifier.zip")
  timeout          = 10
  memory_size      = 128

  depends_on = [aws_iam_role_policy.classifier_logs]
}

resource "aws_apigatewayv2_api" "deploypulse" {
  name          = "deploypulse-http-api"
  protocol_type = "HTTP"

  tags = {
    Project = "DeployPulse"
  }
}

resource "aws_apigatewayv2_integration" "taskflow" {
  api_id                 = aws_apigatewayv2_api.deploypulse.id
  integration_type       = "AWS_PROXY"
  integration_method     = "POST"
  integration_uri        = aws_lambda_function.taskflow.invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_integration" "classifier" {
  api_id                 = aws_apigatewayv2_api.deploypulse.id
  integration_type       = "AWS_PROXY"
  integration_method     = "POST"
  integration_uri        = aws_lambda_function.classifier.invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "tasks_get" {
  api_id    = aws_apigatewayv2_api.deploypulse.id
  route_key = "GET /tasks"
  target    = "integrations/${aws_apigatewayv2_integration.taskflow.id}"
}

resource "aws_apigatewayv2_route" "tasks_post" {
  api_id    = aws_apigatewayv2_api.deploypulse.id
  route_key = "POST /tasks"
  target    = "integrations/${aws_apigatewayv2_integration.taskflow.id}"
}

resource "aws_apigatewayv2_route" "classify_post" {
  api_id    = aws_apigatewayv2_api.deploypulse.id
  route_key = "POST /classify"
  target    = "integrations/${aws_apigatewayv2_integration.classifier.id}"
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.deploypulse.id
  name        = "$default"
  auto_deploy = true

  default_route_settings {
    detailed_metrics_enabled = false
    throttling_burst_limit   = 5
    throttling_rate_limit    = 10
  }

  tags = {
    Project = "DeployPulse"
  }
}

resource "aws_lambda_permission" "api_taskflow" {
  statement_id  = "AllowHttpApiTaskFlow"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.taskflow.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.deploypulse.execution_arn}/*/*"
}

resource "aws_lambda_permission" "api_classifier" {
  statement_id  = "AllowHttpApiClassifier"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.classifier.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.deploypulse.execution_arn}/*/*"
}