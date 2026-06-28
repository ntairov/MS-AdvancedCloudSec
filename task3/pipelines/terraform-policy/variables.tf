variable "region" {
  description = "AWS region for IAM deployment."
  type        = string
  default     = "eu-north-1"
}

variable "iam_user_name" {
  description = "Name of the IAM user."
  type        = string
  default     = "ci-policy-user"
}

variable "iam_policy_name" {
  description = "Name of the IAM policy."
  type        = string
  default     = "ci-ec2-controlled-access"
}
