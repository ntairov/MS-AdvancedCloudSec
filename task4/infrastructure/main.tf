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
  region  = var.region
  profile = var.profile != "" ? var.profile : null
}

# -------------------------------------------------------------------
# AMI: latest Amazon Linux 2023 (x86_64) — region-agnostic
# -------------------------------------------------------------------
data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# -------------------------------------------------------------------
# Networking — default VPC
# -------------------------------------------------------------------
data "aws_vpc" "default" {
  default = true
}

# aws_subnet_ids is deprecated in provider v5; use aws_subnets
data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

# -------------------------------------------------------------------
# IAM role for Jenkins EC2 instance
# -------------------------------------------------------------------
resource "aws_iam_role" "jenkins_role" {
  name = "${var.project_tag}-jenkins-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = { Project = var.project_tag }
}

resource "aws_iam_role_policy_attachment" "ssm_core" {
  role       = aws_iam_role.jenkins_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy" "jenkins_inline_policy" {
  name = "${var.project_tag}-jenkins-inline"
  role = aws_iam_role.jenkins_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "IAMManagement"
        Effect = "Allow"
        Action = [
          "iam:CreateUser",
          "iam:DeleteUser",
          "iam:TagUser",
          "iam:UntagUser",
          "iam:CreatePolicy",
          "iam:DeletePolicy",
          "iam:CreatePolicyVersion",
          "iam:DeletePolicyVersion",
          "iam:AttachUserPolicy",
          "iam:DetachUserPolicy",
          "iam:Get*",
          "iam:List*"
        ]
        Resource = "*"
      },
      {
        Sid      = "STSCallerIdentity"
        Effect   = "Allow"
        Action   = ["sts:GetCallerIdentity"]
        Resource = "*"
      },
      {
        Sid    = "CloudWatchLogs"
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_instance_profile" "jenkins_profile" {
  name = "${var.project_tag}-jenkins-profile"
  role = aws_iam_role.jenkins_role.name
}

# -------------------------------------------------------------------
# Security group — SSH always open (SSM blocked by org SCP)
# -------------------------------------------------------------------
resource "aws_security_group" "jenkins_sg" {
  name        = "${var.project_tag}-jenkins-sg"
  description = "Jenkins controller - SSH access for port-forward tunnel."
  vpc_id      = data.aws_vpc.default.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.allowed_ssh_cidr]
  }

  tags = { Name = "${var.project_tag}-jenkins-sg" }
}

# -------------------------------------------------------------------
# Jenkins EC2 instance
# -------------------------------------------------------------------
resource "aws_instance" "jenkins" {
  ami                         = data.aws_ami.al2023.id
  instance_type               = var.instance_type
  subnet_id                   = tolist(data.aws_subnets.default.ids)[0]
  associate_public_ip_address = true
  iam_instance_profile        = aws_iam_instance_profile.jenkins_profile.name
  vpc_security_group_ids      = [aws_security_group.jenkins_sg.id]
  key_name                    = var.key_name != "" ? var.key_name : null
  user_data                   = file("${path.module}/userdata.sh")

  root_block_device {
    volume_size = 20
    volume_type = "gp3"
  }

  tags = {
    Name        = "${var.project_tag}-jenkins"
    Environment = "devsecops-training"
    Project     = var.project_tag
  }
}
