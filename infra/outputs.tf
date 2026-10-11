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