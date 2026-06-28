variable "region" {
  description = "AWS region to deploy IAM resources."
  type        = string
  default     = "eu-north-1"
}

variable "iam_user_name" {
  description = "Name for the IAM user."
  type        = string
  default     = "ci-terra-user"
}

variable "iam_policy_name" {
  description = "Name for the IAM policy."
  type        = string
  default     = "ci-terra-ec2-limited"
}
