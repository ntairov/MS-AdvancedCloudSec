terraform {
  required_version = ">= 1.6.0"
}

provider "aws" {
  region = var.region
}

resource "aws_iam_user" "ci_user" {
  name          = var.iam_user_name
  force_destroy = true
  tags = {
    Project = "ci-cd-security-homework"
    State   = "remediated"
  }
}

data "aws_iam_policy_document" "ec2_limited" {
  statement {
    sid    = "EC2ReadAndLifecycle"
    effect = "Allow"
    actions = [
      "ec2:DescribeInstances",
      "ec2:DescribeInstanceStatus",
      "ec2:DescribeTags",
      "ec2:DescribeImages",
      "ec2:DescribeVolumes",
      "ec2:StartInstances",
      "ec2:StopInstances",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "ec2_limited" {
  name        = var.iam_policy_name
  description = "Limited EC2 access for CI pipeline."
  policy      = data.aws_iam_policy_document.ec2_limited.json
}

resource "aws_iam_user_policy_attachment" "attach" {
  user       = aws_iam_user.ci_user.name
  policy_arn = aws_iam_policy.ec2_limited.arn
}
