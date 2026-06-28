pipeline {
  agent any

  environment {
    AWS_REGION = "eu-north-1"
    TF_WORKDIR = "terraform-remediated"
    TF_IN_AUTOMATION = "true"
  }

  stages {
    stage('Prepare Workspace') {
      steps {
        sh '''
          rm -rf ${TF_WORKDIR}
          mkdir -p ${TF_WORKDIR}
          mkdir -p /var/lib/jenkins/tfstate

          cat <<'EOF' > ${TF_WORKDIR}/variables.tf
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
EOF

          cat <<'EOF' > ${TF_WORKDIR}/main.tf
terraform {
  required_version = ">= 1.6.0"

  backend "local" {
    path = "/var/lib/jenkins/tfstate/terraform-remediated.tfstate"
  }
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
        sh '''
          cd ${TF_WORKDIR}
          terraform init -input=false
        '''
      }
    }

    stage('Terraform fmt & validate') {
      steps {
        sh '''
          cd ${TF_WORKDIR}
          terraform fmt -check
          terraform validate
        '''
      }
    }

    stage('Trivy Scan (Fail on High/Critical)') {
      steps {
        sh '''
          cd ${TF_WORKDIR}
          trivy config --exit-code 0 --format table --output trivy-report.txt .
          echo "=== Trivy report ==="
          cat trivy-report.txt
          echo "=== Enforcing: no HIGH or CRITICAL findings allowed ==="
          trivy config --exit-code 1 --severity HIGH,CRITICAL .
        '''
      }
    }

    stage('Terraform Plan') {
      steps {
        sh '''
          cd ${TF_WORKDIR}
          terraform plan -input=false -out=tfplan
        '''
      }
    }

    stage('Terraform Apply') {
      steps {
        sh '''
          cd ${TF_WORKDIR}
          terraform apply -input=false -auto-approve tfplan
        '''
      }
    }
  }

  post {
    always {
      archiveArtifacts artifacts: "${TF_WORKDIR}/trivy-report.txt", fingerprint: true
    }
    success {
      echo "Remediated IAM configuration applied. No HIGH/CRITICAL findings."
    }
    failure {
      echo "Pipeline failed — Trivy found HIGH/CRITICAL issues or apply failed."
    }
  }
}
