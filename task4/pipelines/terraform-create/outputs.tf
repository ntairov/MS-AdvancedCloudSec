output "iam_user_arn" {
  description = "ARN of the IAM user."
  value       = aws_iam_user.ci_user.arn
}

output "iam_policy_arn" {
  description = "ARN of the IAM policy."
  value       = aws_iam_policy.ec2_full_access.arn
}
