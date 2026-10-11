
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

# IAM role for TaskFlow Lambda
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

# IAM role for incident classifier Lambda
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

# CloudWatch log groups with 14-day retention
resource "aws_cloudwatch_log_group" "taskflow" {
  name              = "/aws/lambda/deploypulse-taskflow"
  retention_in_days = 14
}

resource "aws_cloudwatch_log_group" "classifier" {
  name              = "/aws/lambda/deploypulse-incident-classifier"
  retention_in_days = 14
}

# TaskFlow Lambda
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

# Incident classifier Lambda
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

# HTTP API
resource "aws_apigatewayv2_api" "deploypulse" {
  name          = "deploypulse-http-api"
  protocol_type = "HTTP"

  tags = {
    Project = "DeployPulse"
  }
}

# API integration for TaskFlow
resource "aws_apigatewayv2_integration" "taskflow" {
  api_id                 = aws_apigatewayv2_api.deploypulse.id
  integration_type       = "AWS_PROXY"
  integration_method     = "POST"
  integration_uri        = aws_lambda_function.taskflow.invoke_arn
  payload_format_version = "2.0"
}

# API integration for classifier
resource "aws_apigatewayv2_integration" "classifier" {
  api_id                 = aws_apigatewayv2_api.deploypulse.id
  integration_type       = "AWS_PROXY"
  integration_method     = "POST"
  integration_uri        = aws_lambda_function.classifier.invoke_arn
  payload_format_version = "2.0"
}

# Cognito User Pool
resource "aws_cognito_user_pool" "deploypulse" {
  name = "deploypulse-users"

  username_attributes      = ["email"]
  auto_verified_attributes = ["email"]

  password_policy {
    minimum_length                   = 12
    require_lowercase                = true
    require_numbers                  = true
    require_symbols                  = true
    require_uppercase                = true
    temporary_password_validity_days = 3
  }

  admin_create_user_config {
    allow_admin_create_user_only = true
  }

  tags = {
    Project     = "DeployPulse"
    Environment = "dev"
  }
}

# Public application client; no client secret
resource "aws_cognito_user_pool_client" "deploypulse" {
  name         = "deploypulse-api-client"
  user_pool_id = aws_cognito_user_pool.deploypulse.id

  generate_secret               = false
  explicit_auth_flows           = ["ALLOW_USER_SRP_AUTH", "ALLOW_USER_PASSWORD_AUTH"]
  prevent_user_existence_errors = "ENABLED"
  enable_token_revocation       = true

  access_token_validity  = 60
  id_token_validity      = 60
  refresh_token_validity = 7

  token_validity_units {
    access_token  = "minutes"
    id_token      = "minutes"
    refresh_token = "days"
  }

  allowed_oauth_flows_user_pool_client = false
}

# JWT authorizer for API Gateway
resource "aws_apigatewayv2_authorizer" "cognito" {
  api_id           = aws_apigatewayv2_api.deploypulse.id
  name             = "deploypulse-cognito-authorizer"
  authorizer_type  = "JWT"
  identity_sources = ["$request.header.Authorization"]

  jwt_configuration {
    audience = [aws_cognito_user_pool_client.deploypulse.id]
    issuer   = "https://cognito-idp.${var.aws_region}.amazonaws.com/${aws_cognito_user_pool.deploypulse.id}"
  }
}

# GET /tasks - Cognito authentication required
resource "aws_apigatewayv2_route" "tasks_get" {
  api_id             = aws_apigatewayv2_api.deploypulse.id
  route_key          = "GET /tasks"
  target             = "integrations/${aws_apigatewayv2_integration.taskflow.id}"
  authorization_type = "JWT"
  authorizer_id      = aws_apigatewayv2_authorizer.cognito.id
}

# POST /tasks - Cognito authentication required
resource "aws_apigatewayv2_route" "tasks_post" {
  api_id             = aws_apigatewayv2_api.deploypulse.id
  route_key          = "POST /tasks"
  target             = "integrations/${aws_apigatewayv2_integration.taskflow.id}"
  authorization_type = "JWT"
  authorizer_id      = aws_apigatewayv2_authorizer.cognito.id
}

# POST /classify - Cognito authentication required
resource "aws_apigatewayv2_route" "classify_post" {
  api_id             = aws_apigatewayv2_api.deploypulse.id
  route_key          = "POST /classify"
  target             = "integrations/${aws_apigatewayv2_integration.classifier.id}"
  authorization_type = "JWT"
  authorizer_id      = aws_apigatewayv2_authorizer.cognito.id
}

# Default stage
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

# Permit API Gateway to invoke TaskFlow
resource "aws_lambda_permission" "api_taskflow" {
  statement_id  = "AllowHttpApiTaskFlow"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.taskflow.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.deploypulse.execution_arn}/*/*"
}

# Permit API Gateway to invoke classifier
resource "aws_lambda_permission" "api_classifier" {
  statement_id  = "AllowHttpApiClassifier"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.classifier.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.deploypulse.execution_arn}/*/*"
}