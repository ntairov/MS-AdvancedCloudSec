#!/bin/bash
set -e

dnf update -y

# Java (Jenkins dependency)
dnf install -y java-17-amazon-corretto git unzip

# Terraform
curl -fsSL https://rpm.releases.hashicorp.com/AmazonLinux/hashicorp.repo \
  | tee /etc/yum.repos.d/hashicorp.repo
dnf install -y terraform

# AWS CLI v2
dnf install -y awscli

# Jenkins
curl -o /etc/yum.repos.d/jenkins.repo \
  https://pkg.jenkins.io/redhat-stable/jenkins.repo
rpm --import https://pkg.jenkins.io/redhat-stable/jenkins.io-2023.key
dnf install -y jenkins

systemctl enable jenkins
systemctl start jenkins
