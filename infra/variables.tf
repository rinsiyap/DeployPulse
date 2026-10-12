variable "aws_region" {
  description = "AWS region for DeployPulse"
  type        = string
  default     = "us-east-2"
}

variable "incident_notification_email" {
  description = "Email address for DeployPulse incident notifications; leave empty to skip email subscription"
  type        = string
  default     = ""
}
