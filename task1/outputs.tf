output "iam_user_arn" {
  description = "ARN of the test IAM user"
  value       = aws_iam_user.test_user.arn
}

output "access_key_id" {
  description = "Access key ID (store securely — do not commit)"
  value       = aws_iam_access_key.test.id
  sensitive   = true
}

output "secret_access_key" {
  description = "Secret access key (store securely — do not commit)"
  value       = aws_iam_access_key.test.secret
  sensitive   = true
}

output "cloudwatch_log_group" {
  description = "CloudWatch log group receiving Security Hub findings"
  value       = aws_cloudwatch_log_group.security_hub.name
}

output "eventbridge_rule_arn" {
  description = "EventBridge rule ARN"
  value       = aws_cloudwatch_event_rule.securityhub_findings.arn
}

output "current_policy" {
  description = "Which policy phase is active"
  value       = var.remediated ? "REMEDIATED: least-privilege (${var.policy_name}-limited)" : "MISCONFIGURED: full-access (${var.policy_name})"
}
