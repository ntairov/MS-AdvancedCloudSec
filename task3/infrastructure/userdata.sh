#!/bin/bash

dnf update -y

# Java 21 required — Jenkins 2.500+ dropped Java 17 support
dnf install -y java-21-amazon-corretto git unzip fontconfig

# Terraform
curl -fsSL https://rpm.releases.hashicorp.com/AmazonLinux/hashicorp.repo \
  | tee /etc/yum.repos.d/hashicorp.repo
dnf install -y terraform

# AWS CLI v2 (pre-installed on AL2023)
dnf install -y awscli || true

# Jenkins — -fsSL required to follow the redirect from pkg.jenkins.io
curl -fsSL -o /etc/yum.repos.d/jenkins.repo \
  https://pkg.jenkins.io/redhat-stable/jenkins.repo
rpm --import https://pkg.jenkins.io/redhat-stable/jenkins.io-2023.key
dnf install -y jenkins

systemctl enable jenkins
systemctl start jenkins
