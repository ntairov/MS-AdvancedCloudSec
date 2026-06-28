terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.region
}

data "aws_caller_identity" "current" {}

resource "aws_iam_user" "ci_user" {
  name          = var.iam_user_name
  force_destroy = true

  tags = {
    Project     = "ci-cd-security-homework"
    Environment = "controlled"
  }
}

data "aws_iam_policy_document" "ec2_limited" {
  statement {
    sid    = "DescribeOnly"
    effect = "Allow"
    actions = [
      "ec2:DescribeInstances",
      "ec2:DescribeInstanceStatus",
      "ec2:DescribeTags",
      "ec2:DescribeImages",
      "ec2:DescribeVolumes"
    ]
    resources = ["*"]
  }

  statement {
    sid    = "LifecycleControl"
    effect = "Allow"
    actions = [
      "ec2:StartInstances",
      "ec2:StopInstances"
    ]
    # Scoped to instances in this account and region only
    resources = [
      "arn:aws:ec2:${var.region}:${data.aws_caller_identity.current.account_id}:instance/*"
    ]
    # Further restricted to instances tagged Environment=controlled
    condition {
      test     = "StringEquals"
      variable = "ec2:ResourceTag/Environment"
      values   = ["controlled"]
    }
  }
}

resource "aws_iam_policy" "ec2_limited" {
  name        = var.iam_policy_name
  description = "Least-privilege EC2 policy for CI automation."
  policy      = data.aws_iam_policy_document.ec2_limited.json
}

resource "aws_iam_user_policy_attachment" "attach" {
  user       = aws_iam_user.ci_user.name
  policy_arn = aws_iam_policy.ec2_limited.arn
}
