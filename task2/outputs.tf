output "cloudtrail_bucket_name" {
  value       = aws_s3_bucket.cloudtrail.bucket
  description = "S3 bucket storing CloudTrail logs."
}

output "opensearch_endpoint" {
  value       = aws_opensearch_domain.siem.endpoint
  description = "OpenSearch HTTPS endpoint."
}

output "sns_topic_arn" {
  value       = aws_sns_topic.security_alerts.arn
  description = "SNS topic ARN for DeleteUser alerts."
}

output "eventbridge_rule_name" {
  value       = aws_cloudwatch_event_rule.delete_user.name
  description = "EventBridge rule that detects IAM DeleteUser."
}

output "cloudwatch_log_group" {
  value       = aws_cloudwatch_log_group.cloudtrail.name
  description = "CloudWatch Logs group for CloudTrail events."
}
