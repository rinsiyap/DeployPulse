output "tasks_table_name" {
  description = "DynamoDB table used by TaskFlow"
  value       = aws_dynamodb_table.tasks.name
}

output "taskflow_lambda_name" {
  description = "TaskFlow Lambda function name"
  value       = aws_lambda_function.taskflow.function_name
}

output "classifier_lambda_name" {
  description = "Incident classifier Lambda function name"
  value       = aws_lambda_function.classifier.function_name
}
output "api_endpoint" {
  description = "Base URL of the DeployPulse HTTP API"
  value       = aws_apigatewayv2_api.deploypulse.api_endpoint
}
output "cognito_user_pool_id" {
  description = "DeployPulse Cognito User Pool ID"
  value       = aws_cognito_user_pool.deploypulse.id
}

output "cognito_client_id" {
  description = "DeployPulse Cognito application client ID"
  value       = aws_cognito_user_pool_client.deploypulse.id
}
output "incidents_table_name" {
  value = aws_dynamodb_table.incidents.name
}

output "incident_queue_url" {
  value = aws_sqs_queue.incident_events.url
}

output "incident_dlq_url" {
  value = aws_sqs_queue.incident_dlq.url
}

output "incident_sns_topic_arn" {
  value = aws_sns_topic.incidents.arn
}
