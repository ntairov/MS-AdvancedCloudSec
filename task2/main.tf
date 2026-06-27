terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.5"
    }
  }
}

provider "aws" {
  region  = var.region
  profile = var.profile
}

data "aws_caller_identity" "current" {}

resource "random_id" "suffix" {
  byte_length = 4
}

locals {
  trail_name        = "${var.project_prefix}-account-trail"
  log_group_name    = "/aws/cloudtrail/${var.project_prefix}"
  firehose_name     = "${var.project_prefix}-ct-firehose"
  opensearch_domain = "${var.project_prefix}-siem"
  backup_bucket     = "${var.project_prefix}-firehose-backup-${random_id.suffix.hex}"
}

# -------------------------------------------------------------------
# S3 — CloudTrail logs
# -------------------------------------------------------------------
resource "aws_s3_bucket" "cloudtrail" {
  bucket        = "${var.project_prefix}-cloudtrail-${random_id.suffix.hex}"
  force_destroy = true

  tags = {
    Project = var.project_prefix
    Purpose = "CloudTrailLogs"
  }
}

resource "aws_s3_bucket_versioning" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "cloudtrail" {
  bucket                  = aws_s3_bucket.cloudtrail.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_policy" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AWSCloudTrailAclCheck"
        Effect    = "Allow"
        Principal = { Service = "cloudtrail.amazonaws.com" }
        Action    = "s3:GetBucketAcl"
        Resource  = aws_s3_bucket.cloudtrail.arn
      },
      {
        Sid       = "AWSCloudTrailWrite"
        Effect    = "Allow"
        Principal = { Service = "cloudtrail.amazonaws.com" }
        Action    = "s3:PutObject"
        Resource  = "${aws_s3_bucket.cloudtrail.arn}/AWSLogs/${data.aws_caller_identity.current.account_id}/*"
        Condition = {
          StringEquals = { "s3:x-amz-acl" = "bucket-owner-full-control" }
        }
      }
    ]
  })

  depends_on = [aws_s3_bucket_public_access_block.cloudtrail]
}

# -------------------------------------------------------------------
# S3 — Firehose failed-document backup
# -------------------------------------------------------------------
resource "aws_s3_bucket" "firehose_backup" {
  bucket        = local.backup_bucket
  force_destroy = true

  tags = {
    Project = var.project_prefix
    Purpose = "FirehoseBackup"
  }
}

resource "aws_s3_bucket_public_access_block" "firehose_backup" {
  bucket                  = aws_s3_bucket.firehose_backup.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "firehose_backup" {
  bucket = aws_s3_bucket.firehose_backup.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# -------------------------------------------------------------------
# CloudWatch Logs group + IAM role for CloudTrail delivery
# -------------------------------------------------------------------
resource "aws_cloudwatch_log_group" "cloudtrail" {
  name              = local.log_group_name
  retention_in_days = 30

  tags = { Project = var.project_prefix }
}

resource "aws_iam_role" "cloudtrail_to_cw" {
  name = "${var.project_prefix}-CloudTrailCWRole"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "cloudtrail.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy" "cloudtrail_to_cw" {
  name = "${var.project_prefix}-CloudTrailCWPolicy"
  role = aws_iam_role.cloudtrail_to_cw.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "logs:CreateLogStream",
        "logs:PutLogEvents",
        "logs:DescribeLogGroups",
        "logs:DescribeLogStreams"
      ]
      Resource = "${aws_cloudwatch_log_group.cloudtrail.arn}:*"
    }]
  })
}

# -------------------------------------------------------------------
# IAM role: CloudWatch Logs → Firehose subscription
# -------------------------------------------------------------------
resource "aws_iam_role" "cloudwatch_to_firehose" {
  name = "${var.project_prefix}-CWLogsFirehoseRole"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "logs.${var.region}.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "cloudwatch_to_firehose" {
  name = "${var.project_prefix}-CWLogsFirehosePolicy"
  role = aws_iam_role.cloudwatch_to_firehose.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["firehose:PutRecord", "firehose:PutRecordBatch"]
      Resource = aws_kinesis_firehose_delivery_stream.cloudtrail_to_os.arn
    }]
  })
}

# -------------------------------------------------------------------
# IAM role: Firehose → OpenSearch + S3 backup
# -------------------------------------------------------------------
resource "aws_iam_role" "firehose_to_opensearch" {
  name = "${var.project_prefix}-FirehoseRole"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "firehose.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "firehose_to_opensearch" {
  name = "${var.project_prefix}-FirehosePolicy"
  role = aws_iam_role.firehose_to_opensearch.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "es:DescribeDomain",
          "es:DescribeDomains",
          "es:DescribeDomainConfig",
          "es:ESHttpPost",
          "es:ESHttpPut"
        ]
        # Both domain ARN and index-level ARN/*  are required
        Resource = [
          aws_opensearch_domain.siem.arn,
          "${aws_opensearch_domain.siem.arn}/*"
        ]
      },
      {
        Effect   = "Allow"
        Action   = ["logs:PutLogEvents"]
        Resource = "arn:aws:logs:${var.region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/kinesisfirehose/*:log-stream:*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:AbortMultipartUpload",
          "s3:GetBucketLocation",
          "s3:GetObject",
          "s3:ListBucket",
          "s3:ListBucketMultipartUploads",
          "s3:PutObject"
        ]
        Resource = [
          aws_s3_bucket.firehose_backup.arn,
          "${aws_s3_bucket.firehose_backup.arn}/*"
        ]
      }
    ]
  })
}

# -------------------------------------------------------------------
# OpenSearch domain (t3.small.search, single-node, dev)
# Fine-grained access control requires encrypt_at_rest + node_to_node
# + enforce_https — all enabled below.
# -------------------------------------------------------------------
resource "aws_opensearch_domain" "siem" {
  domain_name    = local.opensearch_domain
  engine_version = "OpenSearch_2.13"

  cluster_config {
    instance_type          = "t3.small.search"
    instance_count         = 1
    zone_awareness_enabled = false
  }

  ebs_options {
    ebs_enabled = true
    volume_size = 10
    volume_type = "gp3"
  }

  domain_endpoint_options {
    enforce_https       = true
    tls_security_policy = "Policy-Min-TLS-1-2-2019-07"
  }

  node_to_node_encryption {
    enabled = true
  }

  encrypt_at_rest {
    enabled = true
  }

  advanced_security_options {
    enabled                        = true
    internal_user_database_enabled = true
    master_user_options {
      master_user_name     = var.opensearch_master_username
      master_user_password = var.opensearch_master_password
    }
  }

  tags = {
    Project = var.project_prefix
    Purpose = "SIEM"
  }
}

# Separate resource avoids self-reference cycle in access_policies.
# Lab policy: allow all actions from any IP (requires valid AWS auth).
# Tighten to corporate CIDRs or a VPC endpoint for production.
resource "aws_opensearch_domain_policy" "siem" {
  domain_name = aws_opensearch_domain.siem.domain_name

  access_policies = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = { AWS = "*" }
        Action    = "es:*"
        Resource  = "${aws_opensearch_domain.siem.arn}/*"
      }
    ]
  })
}

# -------------------------------------------------------------------
# Kinesis Firehose: CloudWatch Logs → OpenSearch
# s3_configuration must be nested inside opensearch_configuration
# (it is NOT a top-level sibling block when destination = "opensearch")
# -------------------------------------------------------------------
resource "aws_kinesis_firehose_delivery_stream" "cloudtrail_to_os" {
  name        = local.firehose_name
  destination = "opensearch"

  depends_on = [aws_opensearch_domain.siem]

  opensearch_configuration {
    domain_arn         = aws_opensearch_domain.siem.arn
    index_name         = "aws-cloudtrail"
    index_rotation_period = "OneDay"
    role_arn           = aws_iam_role.firehose_to_opensearch.arn
    buffering_interval = var.firehose_buffer_interval
    buffering_size     = var.firehose_buffer_size
    retry_duration     = 300
    s3_backup_mode     = "FailedDocumentsOnly"

    s3_configuration {
      bucket_arn         = aws_s3_bucket.firehose_backup.arn
      role_arn           = aws_iam_role.firehose_to_opensearch.arn
      buffering_size     = 5
      buffering_interval = 300
      compression_format = "GZIP"
    }
  }

  tags = { Project = var.project_prefix }
}

# -------------------------------------------------------------------
# CloudWatch Logs subscription filter → Firehose
# -------------------------------------------------------------------
resource "aws_cloudwatch_log_subscription_filter" "cloudtrail_to_firehose" {
  name            = "${var.project_prefix}-ct-subscription"
  log_group_name  = aws_cloudwatch_log_group.cloudtrail.name
  filter_pattern  = ""
  destination_arn = aws_kinesis_firehose_delivery_stream.cloudtrail_to_os.arn
  role_arn        = aws_iam_role.cloudwatch_to_firehose.arn

  depends_on = [aws_kinesis_firehose_delivery_stream.cloudtrail_to_os]
}

# -------------------------------------------------------------------
# CloudTrail: account-level trail, all regions
# -------------------------------------------------------------------
resource "aws_cloudtrail" "account_trail" {
  name                          = local.trail_name
  s3_bucket_name                = aws_s3_bucket.cloudtrail.id
  include_global_service_events = true
  is_multi_region_trail         = true
  enable_log_file_validation    = true

  cloud_watch_logs_group_arn = "${aws_cloudwatch_log_group.cloudtrail.arn}:*"
  cloud_watch_logs_role_arn      = aws_iam_role.cloudtrail_to_cw.arn

  event_selector {
    include_management_events = true
    read_write_type           = "All"
  }

  depends_on = [
    aws_iam_role_policy.cloudtrail_to_cw,
    aws_s3_bucket_policy.cloudtrail
  ]

  tags = { Project = var.project_prefix }
}

# -------------------------------------------------------------------
# SNS topic + email subscription
# -------------------------------------------------------------------
resource "aws_sns_topic" "security_alerts" {
  name = "${var.project_prefix}-deleteuser-alerts"

  tags = { Project = var.project_prefix }
}

resource "aws_sns_topic_policy" "security_alerts" {
  arn = aws_sns_topic.security_alerts.arn
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "AllowEventBridgePublish"
      Effect    = "Allow"
      Principal = { Service = "events.amazonaws.com" }
      Action    = "sns:Publish"
      Resource  = aws_sns_topic.security_alerts.arn
    }]
  })
}

resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.security_alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email

  lifecycle {
    ignore_changes = all
  }
}

# -------------------------------------------------------------------
# EventBridge rule: detect IAM DeleteUser via CloudTrail
# NOTE: IAM is a global service — its CloudTrail events are delivered
# to EventBridge in us-east-1 only. In this environment the SCP
# restricts all operations to eu-north-1, so this rule cannot fire
# for IAM events. Documented as a known limitation in SUBMISSION.md.
# -------------------------------------------------------------------
resource "aws_cloudwatch_event_rule" "delete_user" {
  name        = "${var.project_prefix}-delete-user"
  description = "Detects AWS IAM DeleteUser API calls via CloudTrail."

  event_pattern = jsonencode({
    source      = ["aws.iam"]
    detail-type = ["AWS API Call via CloudTrail"]
    detail = {
      eventSource = ["iam.amazonaws.com"]
      eventName   = ["DeleteUser"]
    }
  })
}

resource "aws_cloudwatch_event_target" "sns_alert" {
  rule      = aws_cloudwatch_event_rule.delete_user.name
  target_id = "send-to-sns"
  arn       = aws_sns_topic.security_alerts.arn
}

# -------------------------------------------------------------------
# CloudWatch metric filter + alarm (secondary detection signal)
# -------------------------------------------------------------------
resource "aws_cloudwatch_log_metric_filter" "delete_user_metric" {
  name           = "${var.project_prefix}-DeleteUserMetric"
  log_group_name = aws_cloudwatch_log_group.cloudtrail.name
  pattern        = "{ $.eventSource = \"iam.amazonaws.com\" && $.eventName = \"DeleteUser\" }"

  metric_transformation {
    name      = "DeleteUserCount"
    namespace = "SIEMLab"
    value     = "1"
  }
}

resource "aws_cloudwatch_metric_alarm" "delete_user_alarm" {
  alarm_name          = "${var.project_prefix}-DeleteUserAlarm"
  alarm_description   = "Alarm when the DeleteUser API is invoked."
  namespace           = "SIEMLab"
  metric_name         = "DeleteUserCount"
  statistic           = "Sum"
  period              = 60
  evaluation_periods  = 1
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.security_alerts.arn]
}
