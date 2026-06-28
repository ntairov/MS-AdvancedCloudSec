pipeline {
  agent any

  environment {
    AWS_REGION = "eu-north-1"
    TF_WORKDIR = "terraform-create"
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
  default     = "ci-terra-ec2-full"
}
EOF

          cat <<'EOF' > ${TF_WORKDIR}/main.tf
terraform {
  required_version = ">= 1.6.0"

  backend "local" {
    path = "/var/lib/jenkins/tfstate/terraform-create.tfstate"
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
EOF

          cat <<'EOF' > ${TF_WORKDIR}/outputs.tf
output "iam_user_arn" {
  description = "ARN of the IAM user."
  value       = aws_iam_user.ci_user.arn
}

output "iam_policy_arn" {
  description = "ARN of the IAM policy."
  value       = aws_iam_policy.ec2_full_access.arn
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

    stage('Trivy Scan') {
      steps {
        sh '''
          cd ${TF_WORKDIR}
          trivy config --exit-code 0 --format table --output trivy-report.txt .
          echo "=== Trivy findings (informational — pipeline continues) ==="
          cat trivy-report.txt
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
      echo "Insecure IAM resources created. Trivy findings saved as artifact."
    }
    failure {
      echo "Pipeline failed. Check console logs."
    }
  }
}
