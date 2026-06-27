# ── Security Hub ──────────────────────────────────────────────────────────────

resource "aws_securityhub_account" "this" {}

resource "aws_securityhub_standards_subscription" "fsbp" {
  standards_arn = "arn:aws:securityhub:${var.aws_region}::standards/aws-foundational-security-best-practices/v/1.0.0"
  depends_on    = [aws_securityhub_account.this]
}

# ── IAM User ──────────────────────────────────────────────────────────────────

resource "aws_iam_user" "test_user" {
  name          = var.user_name
  force_destroy = true
}

resource "aws_iam_access_key" "test" {
  user = aws_iam_user.test_user.name
}

# ── Phase 1: Overly permissive policy (misconfiguration) ──────────────────────

data "aws_iam_policy_document" "overly_permissive" {
  statement {
    sid       = "FullAccess"
    effect    = "Allow"
    actions   = ["*"]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "full_access" {
  count  = var.remediated ? 0 : 1
  name   = var.policy_name
  policy = data.aws_iam_policy_document.overly_permissive.json
}

resource "aws_iam_user_policy_attachment" "full_access_attach" {
  count      = var.remediated ? 0 : 1
  user       = aws_iam_user.test_user.name
  policy_arn = aws_iam_policy.full_access[0].arn
}

# ── Phase 2: Least-privilege policy (remediation) ─────────────────────────────

data "aws_iam_policy_document" "least_privilege" {
  statement {
    sid    = "LeastPrivilege"
    effect = "Allow"
    actions = [
      "iam:ListUsers",
      "iam:GetUser",
      "iam:ListAccessKeys",
      "cloudwatch:ListDashboards",
      "cloudwatch:GetDashboard"
    ]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "limited_access" {
  count  = var.remediated ? 1 : 0
  name   = "${var.policy_name}-limited"
  policy = data.aws_iam_policy_document.least_privilege.json
}

resource "aws_iam_user_policy_attachment" "limited_access_attach" {
  count      = var.remediated ? 1 : 0
  user       = aws_iam_user.test_user.name
  policy_arn = aws_iam_policy.limited_access[0].arn
}

# ── CloudWatch Log Group ───────────────────────────────────────────────────────

resource "aws_cloudwatch_log_group" "security_hub" {
  name              = var.log_group_name
  retention_in_days = 7
}

# Resource policy: allows EventBridge to write logs directly (no IAM role needed)
resource "aws_cloudwatch_log_resource_policy" "eventbridge_to_cw" {
  policy_name = "paysecure-eventbridge-to-cloudwatch"
  policy_document = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "AllowEventBridgePutLogs"
      Effect = "Allow"
      Principal = {
        Service = ["events.amazonaws.com", "delivery.logs.amazonaws.com"]
      }
      Action = [
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ]
      Resource = "${aws_cloudwatch_log_group.security_hub.arn}:*"
    }]
  })
}

# ── EventBridge: Capture all Security Hub findings ────────────────────────────

resource "aws_cloudwatch_event_rule" "securityhub_findings" {
  name        = "paysecure-securityhub-findings"
  description = "Capture all Security Hub findings for PaySecure homework"

  event_pattern = jsonencode({
    source      = ["aws.securityhub"]
    detail-type = ["Security Hub Findings - Imported"]
  })
}

resource "aws_cloudwatch_event_target" "log_target" {
  rule      = aws_cloudwatch_event_rule.securityhub_findings.name
  target_id = "send-to-cloudwatch-logs"
  arn       = aws_cloudwatch_log_group.security_hub.arn
}
