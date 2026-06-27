variable "aws_region" {
  description = "AWS region for deployment"
  type        = string
  default     = "eu-north-1"
}

variable "aws_profile" {
  description = "AWS CLI named profile"
  type        = string
  default     = "itpu"
}

variable "user_name" {
  description = "IAM user name for the test"
  type        = string
  default     = "paysecure-test-user"
}

variable "policy_name" {
  description = "IAM policy name"
  type        = string
  default     = "paysecure-test-policy"
}

variable "log_group_name" {
  description = "CloudWatch log group for Security Hub findings"
  type        = string
  default     = "/aws/events/paysecure-security-hub"
}

# Toggle: false = overly permissive (Phase 1), true = least privilege (Phase 2)
variable "remediated" {
  description = "Set to true to apply least-privilege remediation"
  type        = bool
  default     = false
}
