pipeline {
  agent any

  environment {
    AWS_REGION = "eu-north-1"
    TF_WORKDIR = "terraform-policy"
    TF_IN_AUTOMATION = "true"
  }

  stages {
    stage('Prepare Workspace') {
      steps {
        sh '''
          rm -rf ${TF_WORKDIR}
          mkdir -p ${TF_WORKDIR}

          cat <<'EOF' > ${TF_WORKDIR}/variables.tf
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
EOF

          cat <<'EOF' > ${TF_WORKDIR}/main.tf
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
    resources = [
      "arn:aws:ec2:${var.region}:${data.aws_caller_identity.current.account_id}:instance/*"
    ]
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
EOF

          cat <<'EOF' > ${TF_WORKDIR}/outputs.tf
output "iam_user_arn" {
  description = "ARN of the IAM user."
  value       = aws_iam_user.ci_user.arn
}

output "iam_policy_arn" {
  description = "ARN of the IAM policy."
  value       = aws_iam_policy.ec2_limited.arn
}
EOF
        '''
      }
    }

    stage('Terraform Init') {
      steps {
        sh 'cd ${TF_WORKDIR} && terraform init -input=false'
      }
    }

    stage('Terraform Format & Validate') {
      steps {
        sh '''
          cd ${TF_WORKDIR}
          terraform fmt -check
          terraform validate
        '''
      }
    }

    stage('Terraform Plan') {
      steps {
        sh 'cd ${TF_WORKDIR} && terraform plan -input=false -out=tfplan'
      }
    }

    stage('Terraform Apply') {
      steps {
        sh 'cd ${TF_WORKDIR} && terraform apply -input=false -auto-approve tfplan'
      }
    }
  }

  post {
    success {
      echo "Hardened IAM policy deployed successfully."
    }
    failure {
      echo "Pipeline failed. Review console output above."
    }
  }
}
