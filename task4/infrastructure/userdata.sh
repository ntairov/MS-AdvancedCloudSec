#!/bin/bash
set -e

dnf update -y

# Java 21 required — Jenkins 2.500+ dropped Java 17 support
dnf install -y java-21-amazon-corretto git unzip fontconfig

# Terraform
curl -fsSL https://rpm.releases.hashicorp.com/AmazonLinux/hashicorp.repo \
  | tee /etc/yum.repos.d/hashicorp.repo
dnf install -y terraform

# AWS CLI v2 (pre-installed on AL2023)
dnf install -y awscli || true

# Trivy — via official RPM repo
cat > /etc/yum.repos.d/trivy.repo <<'TRIVYREPO'
[trivy]
name=Trivy repository
baseurl=https://aquasecurity.github.io/trivy-repo/rpm/releases/$basearch/
gpgcheck=1
enabled=1
gpgkey=https://aquasecurity.github.io/trivy-repo/rpm/public.key
TRIVYREPO
dnf install -y trivy

# Jenkins — -fsSL required to follow the pkg.jenkins.io redirect
curl -fsSL -o /etc/yum.repos.d/jenkins.repo \
  https://pkg.jenkins.io/redhat-stable/jenkins.repo
rpm --import https://pkg.jenkins.io/redhat-stable/jenkins.io-2023.key
dnf install -y jenkins

# Persistent Terraform state directory shared across pipeline jobs
mkdir -p /var/lib/jenkins/tfstate
chown jenkins:jenkins /var/lib/jenkins/tfstate

systemctl enable jenkins
systemctl start jenkins
