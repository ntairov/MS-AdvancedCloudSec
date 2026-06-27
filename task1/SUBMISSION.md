# Automated Detection and Remediation of IAM Policy Misconfiguration in AWS

**Student Name:** Nazim Tairov
**Course Name:** Cloud Security Engineering
**Date:** June 27, 2026

---

## a. Executive Summary

This project demonstrates an end-to-end automated security pipeline for detecting and remediating IAM policy misconfigurations in AWS. As a cloud security engineer for PaySecure — a payment platform subject to PCI DSS and GDPR — I reproduced a real-world scenario where an IAM user was provisioned with an overly permissive policy granting full administrative access (`Action: "*", Resource: "*"`). Using Terraform, I deployed the misconfigured environment in AWS (eu-north-1), enabled AWS Security Hub with the AWS Foundational Security Best Practices (FSBP) standard, and waited for automated detection. Security Hub identified three findings against the policy (HIGH, MEDIUM, LOW severity). Remediation was applied by replacing the full-access policy with a least-privilege policy scoped to five specific IAM and CloudWatch read actions, executed via a single Terraform variable flag (`remediated=true`). Security Hub automatically resolved all findings upon detecting the policy change. All resources were subsequently destroyed via `terraform destroy`, demonstrating a complete, reproducible, and cost-conscious security workflow.

---

## b. Architecture & Tools Overview

### Tools Used

| Tool | Purpose |
|---|---|
| Terraform v1.5+ | Infrastructure as Code — provision, remediate, and destroy all resources |
| AWS Security Hub | Automated security findings aggregation and compliance evaluation |
| AWS FSBP Standard | ~300 controls evaluating AWS resources against security best practices |
| AWS IAM | Identity and Access Management — user, policy, access key management |
| Amazon EventBridge | Event routing — captures Security Hub findings |
| Amazon CloudWatch Logs | Log storage — receives Security Hub finding events |
| AWS CLI v2 | CLI queries to verify findings programmatically |

### Architecture Flow

```
┌─────────────────────────────────────────────────────────┐
│                    Terraform (IaC)                       │
│  variables.tf → providers.tf → main.tf → outputs.tf     │
└────────────────────────┬────────────────────────────────┘
                         │ terraform apply
                         ▼
┌─────────────────────────────────────────────────────────┐
│                    AWS IAM                               │
│  paysecure-test-user                                     │
│  paysecure-test-policy  (Action:*, Resource:*)  ◄──────┐ │
└────────────────────────┬────────────────────────────────┘ │
                         │ FSBP evaluates                   │
                         ▼                                  │
┌─────────────────────────────────────────────────────────┐ │
│               AWS Security Hub (FSBP)                   │ │
│  IAM.1 FAILED - HIGH  (full * privileges)               │ │
│  IAM.6 FAILED - MEDIUM (KMS decryption wildcard)        │ │
│  IAM.21 FAILED - LOW   (wildcard service actions)       │ │
└────────────────────────┬────────────────────────────────┘ │
                         │                                  │
                         ▼                                  │
┌─────────────────────────────────────────────────────────┐ │
│               Amazon EventBridge                        │ │
│  Rule: source = aws.securityhub                         │ │
└────────────────────────┬────────────────────────────────┘ │
                         │                                  │
                         ▼                                  │
┌─────────────────────────────────────────────────────────┐ │
│           CloudWatch Log Group                          │ │
│  /aws/events/paysecure-security-hub                     │ │
└─────────────────────────────────────────────────────────┘ │
                                                            │
terraform apply -var="remediated=true" ────────────────────┘
  Destroys full-access policy
  Creates least-privilege policy
  Security Hub → all findings RESOLVED
```

---

## c. Implementation Steps

### 1. Environment Setup

**Prerequisites:**
- AWS CLI v2 configured with named profile `itpu`
- Terraform v1.5+
- AWS account with Security Hub enabled in `eu-north-1`

**Directory structure created:**
```
paysecure-security-hw/
├── providers.tf
├── variables.tf
├── main.tf
├── outputs.tf
└── README.md
```

**providers.tf:**
```hcl
terraform {
  required_version = ">= 1.3.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region  = var.aws_region
  profile = var.aws_profile
}
```

**variables.tf** (key variables):
```hcl
variable "aws_region"  { default = "eu-north-1" }
variable "aws_profile" { default = "itpu" }
variable "user_name"   { default = "paysecure-test-user" }
variable "policy_name" { default = "paysecure-test-policy" }

# Toggle: false = Phase 1 (misconfigured), true = Phase 2 (remediated)
variable "remediated" {
  type    = bool
  default = false
}
```

### 2. Phase 1 — Deploy Misconfigured Environment

The misconfigured policy grants unrestricted access to all AWS services and resources:

```hcl
data "aws_iam_policy_document" "overly_permissive" {
  statement {
    sid       = "FullAccess"
    effect    = "Allow"
    actions   = ["*"]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "full_access" {
  count  = var.remediated ? 0 : 1
  name   = var.policy_name
  policy = data.aws_iam_policy_document.overly_permissive.json
}
```

The `count = var.remediated ? 0 : 1` pattern means:
- When `remediated = false` → `count = 1` → resource is **created**
- When `remediated = true` → `count = 0` → resource is **destroyed**

**Deploy command:**
```bash
terraform init
terraform apply
```

**Output:**
```
aws_iam_user.test_user: Creating...
aws_iam_policy.full_access[0]: Creating...
aws_iam_user_policy_attachment.full_access_attach[0]: Creating...
aws_securityhub_account.this: Creating...
aws_securityhub_standards_subscription.fsbp: Creating...

Apply complete! Resources: 8 added, 0 changed, 0 destroyed.
```

### 3. EventBridge → CloudWatch Logs Wiring

All Security Hub findings are captured by EventBridge and routed to CloudWatch for audit logging:

```hcl
resource "aws_cloudwatch_log_resource_policy" "eventbridge_to_cw" {
  policy_name = "paysecure-eventbridge-to-cloudwatch"
  policy_document = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = ["events.amazonaws.com"] }
      Action    = ["logs:CreateLogStream", "logs:PutLogEvents"]
      Resource  = "${aws_cloudwatch_log_group.security_hub.arn}:*"
    }]
  })
}

resource "aws_cloudwatch_event_rule" "securityhub_findings" {
  name          = "paysecure-securityhub-findings"
  event_pattern = jsonencode({
    source      = ["aws.securityhub"]
    detail-type = ["Security Hub Findings - Imported"]
  })
}
```

---

## d. Findings & Remediation Validation

### Before Remediation — Security Hub Findings

After waiting ~15 minutes for FSBP to complete its initial scan, three findings were generated against `paysecure-test-policy`:

**CLI query used:**
```bash
aws securityhub get-findings \
  --profile itpu \
  --region eu-north-1 \
  --filters '{"ResourceType":[{"Value":"AwsIamPolicy","Comparison":"EQUALS"}]}' \
  --query 'Findings[*].{Title:Title,Severity:Severity.Label,Resource:Resources[0].Id,Status:Compliance.Status}' \
  --output table
```

**CLI output:**
```
+---------------------------------------------------------+-----------+---------+----------------------------------------------------------------+
|                        Resource                         | Severity  | Status  |                         Title                                  |
+---------------------------------------------------------+-----------+---------+----------------------------------------------------------------+
| arn:aws:iam::562123137719:policy/paysecure-test-policy  |  HIGH     |  FAILED | IAM policies should not allow full "*" administrative privs    |
| arn:aws:iam::562123137719:policy/paysecure-test-policy  |  MEDIUM   |  FAILED | IAM customer managed policies should not allow KMS decryption  |
| arn:aws:iam::562123137719:policy/paysecure-test-policy  |  LOW      |  FAILED | IAM customer managed policies should not allow wildcard actions|
+---------------------------------------------------------+-----------+---------+----------------------------------------------------------------+
```

**[INSERT SCREENSHOT 1 HERE — Security Hub console showing 3 FAILED findings]**

### Remediation — Least Privilege Policy

The overly permissive policy was replaced with a scoped policy granting only the minimum required permissions:

```hcl
data "aws_iam_policy_document" "least_privilege" {
  statement {
    sid    = "LeastPrivilege"
    effect = "Allow"
    actions = [
      "iam:ListUsers",
      "iam:GetUser",
      "iam:ListAccessKeys",
      "cloudwatch:ListDashboards",
      "cloudwatch:GetDashboard"
    ]
    resources = ["*"]
  }
}
```

**Remediation command:**
```bash
terraform apply -var="remediated=true"
```

Terraform executed the following changes in one operation:
- **Destroyed:** `aws_iam_policy.full_access[0]`
- **Destroyed:** `aws_iam_user_policy_attachment.full_access_attach[0]`
- **Created:** `aws_iam_policy.limited_access[0]`
- **Created:** `aws_iam_user_policy_attachment.limited_access_attach[0]`

### After Remediation — Findings Resolved

Security Hub automatically detected the policy change and resolved all findings:

**CLI output after remediation:**
```
+------------------------------------------------------------------+----------------+---------+----------------------------------------------------------------+
|                           Resource                               |   Severity     | Status  |                         Title                                  |
+------------------------------------------------------------------+----------------+---------+----------------------------------------------------------------+
| arn:aws:iam::562123137719:policy/paysecure-test-policy-limited   | INFORMATIONAL  |  PASSED | IAM policies should not allow full "*" administrative privs    |
| arn:aws:iam::562123137719:policy/paysecure-test-policy-limited   | INFORMATIONAL  |  PASSED | IAM customer managed policies should not allow KMS decryption  |
| arn:aws:iam::562123137719:policy/paysecure-test-policy-limited   | INFORMATIONAL  |  PASSED | IAM customer managed policies should not allow wildcard actions|
+------------------------------------------------------------------+----------------+---------+----------------------------------------------------------------+
```

**[INSERT SCREENSHOT 2 HERE — Security Hub console showing all findings RESOLVED]**

### Compliance Implications

**PCI DSS Requirement 7 — Restrict access to system components and cardholder data by business need-to-know:**
The original `Action: *, Resource: *` policy directly violates PCI DSS Req 7.2, which mandates that access rights are granted based on job classification and function (least privilege). An IAM user with full administrative access could read, modify, or delete cardholder data stores, encryption keys, and audit logs — all prohibited under PCI DSS. The remediated policy scopes access to only the read operations required for the user's role.

**GDPR Article 25 — Data Protection by Design and by Default:**
GDPR requires that data protection principles (including data minimisation) are implemented by design. Granting wildcard IAM permissions violates this principle — a user with `iam:*` and `s3:*` could access personal data stores without business justification. The least-privilege remediation directly implements GDPR's data minimisation requirement by ensuring users can only perform actions explicitly required for their role.

---

## e. Cleanup & Cost Considerations

### Cleanup Steps

All resources were destroyed using:
```bash
terraform destroy
```

Resources removed:
- IAM user `paysecure-test-user`
- IAM policy `paysecure-test-policy-limited`
- IAM access key
- CloudWatch Log Group `/aws/events/paysecure-security-hub`
- EventBridge rule `paysecure-securityhub-findings`
- Security Hub FSBP standards subscription

**Security Hub account** was left enabled (can be disabled with):
```bash
aws securityhub disable-security-hub --profile itpu --region eu-north-1
```

### Why Cleanup Matters

1. **Cost:** Security Hub charges per finding ingested (~$0.0030/finding). An account with active standards continuously generates findings — leaving it running accumulates cost with no benefit after the exercise.
2. **Security:** IAM access keys left active are a credential exposure risk. `terraform destroy` removes them immediately.
3. **Compliance:** Unused IAM users with access keys violate the same FSBP controls we just demonstrated — creating circular findings.
4. **State hygiene:** `terraform.tfstate` contains resource IDs and sensitive outputs — it must not be committed to VCS and should be deleted after the exercise.

---

## f. Challenges & Lessons Learned

**1. Security Hub initialization delay**
FSBP takes 15–30 minutes to complete its first scan after being enabled. Initial queries returned empty results, requiring patience and repeated polling. Lesson: in production, Security Hub should be enabled as part of account baseline — not enabled reactively after a misconfiguration is created.

**2. SSO session expiry**
AWS SSO sessions expire after a set period. Running `terraform apply` or `aws securityhub get-findings` after a session timeout required re-running `aws sso login --profile itpu`. Lesson: for automation pipelines, use IAM roles with instance profiles rather than SSO sessions.

**3. Handling secrets in Terraform outputs**
The IAM access key secret is exposed in `terraform output`. Marking outputs as `sensitive = true` prevents accidental display in logs but the value still exists in `terraform.tfstate`. Lesson: never commit `.tfstate` to VCS; use remote state with encryption (S3 + DynamoDB) in production.

**4. Duplicate EventBridge target issue**
The task template had a duplicate `aws_cloudwatch_event_target` resource with the same `target_id`, which would cause a Terraform conflict. This was resolved by using a CloudWatch log group resource policy instead of an IAM role, simplifying the architecture.

**5. Security Hub new console UI**
The AWS Console for Security Hub was recently redesigned — "Security standards" is now under "Posture management". Always verify the current UI rather than relying on older documentation.

---

## g. Appendix

### Terraform Files

**main.tf (full):**
```hcl
resource "aws_securityhub_account" "this" {}

resource "aws_securityhub_standards_subscription" "fsbp" {
  standards_arn = "arn:aws:securityhub:${var.aws_region}::standards/aws-foundational-security-best-practices/v/1.0.0"
  depends_on    = [aws_securityhub_account.this]
}

resource "aws_iam_user" "test_user" {
  name          = var.user_name
  force_destroy = true
}

resource "aws_iam_access_key" "test" {
  user = aws_iam_user.test_user.name
}

data "aws_iam_policy_document" "overly_permissive" {
  statement {
    sid       = "FullAccess"
    effect    = "Allow"
    actions   = ["*"]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "full_access" {
  count  = var.remediated ? 0 : 1
  name   = var.policy_name
  policy = data.aws_iam_policy_document.overly_permissive.json
}

resource "aws_iam_user_policy_attachment" "full_access_attach" {
  count      = var.remediated ? 0 : 1
  user       = aws_iam_user.test_user.name
  policy_arn = aws_iam_policy.full_access[0].arn
}

data "aws_iam_policy_document" "least_privilege" {
  statement {
    sid    = "LeastPrivilege"
    effect = "Allow"
    actions = [
      "iam:ListUsers",
      "iam:GetUser",
      "iam:ListAccessKeys",
      "cloudwatch:ListDashboards",
      "cloudwatch:GetDashboard"
    ]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "limited_access" {
  count  = var.remediated ? 1 : 0
  name   = "${var.policy_name}-limited"
  policy = data.aws_iam_policy_document.least_privilege.json
}

resource "aws_iam_user_policy_attachment" "limited_access_attach" {
  count      = var.remediated ? 1 : 0
  user       = aws_iam_user.test_user.name
  policy_arn = aws_iam_policy.limited_access[0].arn
}

resource "aws_cloudwatch_log_group" "security_hub" {
  name              = var.log_group_name
  retention_in_days = 7
}

resource "aws_cloudwatch_log_resource_policy" "eventbridge_to_cw" {
  policy_name = "paysecure-eventbridge-to-cloudwatch"
  policy_document = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "AllowEventBridgePutLogs"
      Effect = "Allow"
      Principal = { Service = ["events.amazonaws.com"] }
      Action   = ["logs:CreateLogStream", "logs:PutLogEvents"]
      Resource = "${aws_cloudwatch_log_group.security_hub.arn}:*"
    }]
  })
}

resource "aws_cloudwatch_event_rule" "securityhub_findings" {
  name        = "paysecure-securityhub-findings"
  description = "Capture all Security Hub findings for PaySecure homework"
  event_pattern = jsonencode({
    source      = ["aws.securityhub"]
    detail-type = ["Security Hub Findings - Imported"]
  })
}

resource "aws_cloudwatch_event_target" "log_target" {
  rule      = aws_cloudwatch_event_rule.securityhub_findings.name
  target_id = "send-to-cloudwatch-logs"
  arn       = aws_cloudwatch_log_group.security_hub.arn
}
```

### AWS CLI Commands Reference

```bash
# Login to AWS SSO
aws sso login --profile itpu

# Deploy misconfiguration (Phase 1)
terraform init && terraform apply

# Query Security Hub for IAM policy findings
aws securityhub get-findings \
  --profile itpu --region eu-north-1 \
  --filters '{"ResourceType":[{"Value":"AwsIamPolicy","Comparison":"EQUALS"}]}' \
  --query 'Findings[*].{Title:Title,Severity:Severity.Label,Resource:Resources[0].Id,Status:Compliance.Status}' \
  --output table

# Verify which policies are attached to the user
aws iam list-attached-user-policies \
  --user-name paysecure-test-user \
  --profile itpu

# Apply remediation (Phase 2)
terraform apply -var="remediated=true"

# Cleanup
terraform destroy
```

### Additional Resources

- AWS FSBP Standard: https://docs.aws.amazon.com/securityhub/latest/userguide/fsbp-standard.html
- IAM Least Privilege Best Practices: https://docs.aws.amazon.com/IAM/latest/UserGuide/best-practices.html
- PCI DSS Requirement 7: https://www.pcisecuritystandards.org/
- GDPR Article 25 (Data Protection by Design): https://gdpr.eu/article-25-data-protection-by-design/
- Terraform AWS Provider: https://registry.terraform.io/providers/hashicorp/aws/latest/docs
