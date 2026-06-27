variable "project_prefix" {
  description = "Unique prefix for all AWS resources (lowercase letters and numbers only, max 23 chars)."
  type        = string
}

variable "region" {
  description = "AWS region for the deployment."
  type        = string
}

variable "profile" {
  description = "AWS CLI profile name."
  type        = string
}

variable "opensearch_master_username" {
  description = "Master username for the OpenSearch domain."
  type        = string
  sensitive   = true
}

variable "opensearch_master_password" {
  description = "Master password for the OpenSearch domain (min 8 chars, requires uppercase, lowercase, number, special char)."
  type        = string
  sensitive   = true
}

variable "alert_email" {
  description = "Email address that receives SNS alerts."
  type        = string
}

variable "firehose_buffer_interval" {
  description = "Firehose buffer interval in seconds (60-900)."
  type        = number
  default     = 60
}

variable "firehose_buffer_size" {
  description = "Firehose buffer size in MB (1-100)."
  type        = number
  default     = 5
}
