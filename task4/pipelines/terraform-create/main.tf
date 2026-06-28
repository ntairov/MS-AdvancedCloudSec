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
    State   = "insecure"
  }
}

data "aws_iam_policy_document" "ec2_full_access" {
  statement {
    sid       = "EC2FullAccess"
    effect    = "Allow"
    actions   = ["ec2:*"]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "ec2_full_access" {
  name        = var.iam_policy_name
  description = "Full EC2 access for CI pipeline (intentional misconfiguration)."
  policy      = data.aws_iam_policy_document.ec2_full_access.json
}

resource "aws_iam_user_policy_attachment" "attach" {
  user       = aws_iam_user.ci_user.name
  policy_arn = aws_iam_policy.ec2_full_access.arn
}
