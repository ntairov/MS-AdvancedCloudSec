# Nazim Tairov — PT4 Homework
## Integrate Security Testing into a CI/CD Pipeline Using Jenkins

**Course:** MS Advanced Cloud Security  
**Date:** June 2026

---

## 1. Introduction & Objectives

This lab extends the Jenkins CI/CD pipeline from PT3 with integrated security scanning via Trivy. The pipeline demonstrates a complete DevSecOps lifecycle: deploy intentionally misconfigured IAM resources, scan with Trivy to detect issues, destroy them, then redeploy a remediated configuration that passes enforced security gates.

**Objectives met:**
- Jenkins controller on EC2 with no static credentials (instance role)
- 4-pipeline lifecycle: create → destroy → remediate → cleanup
- Trivy IaC scanning integrated at two enforcement levels (informational vs. blocking)
- Terraform state persisted between create/destroy job pairs via local backend

---

## 2. Architecture & Tooling Overview

```
Local machine (SSH tunnel :8080)
        │
        ▼
EC2 t3.medium — Jenkins 2.x (eu-north-1)
        │  EC2 instance role (no static keys)
        ▼
Terraform (inline in Jenkinsfiles)
        │
        ├─ terraform-create job ──► IAM user + ec2:* policy (insecure)
        │       └─ Trivy scan (exit-code 0 — informational)
        │
        ├─ terraform-destroy job ──► destroys insecure resources
        │
        ├─ terraform-remediate job ──► IAM user + 7 specific EC2 actions
        │       └─ Trivy scan (exit-code 1 — blocks on HIGH/CRITICAL)
        │
        └─ terraform-cleanup job ──► destroys remediated resources
```

| Tool | Version | Purpose |
|---|---|---|
| Terraform | 1.15.x | IAM resource provisioning |
| Jenkins | 2.x | CI/CD pipeline orchestration |
| Java | 21 (Amazon Corretto) | Jenkins runtime |
| Trivy | 0.71.2 | IaC misconfiguration scanning |
| AWS CLI | 2.x | Verification |
| EC2 t3.medium | — | Jenkins host (20GB gp3) |

**Key security decisions:**
- Jenkins authenticates to AWS via EC2 instance role — no access keys anywhere
- Jenkins UI not exposed publicly — SSH tunnel only (port 8080 not in security group)
- Terraform state persisted at `/var/lib/jenkins/tfstate/` — shared between create/destroy job pairs via `backend "local"` with absolute path

---

## 3. Implementation Steps

### 3.1 Jenkins Infrastructure

Terraform in `infrastructure/` provisions:
- EC2 instance (t3.medium, Amazon Linux 2023, dynamic AMI lookup, 20GB gp3)
- IAM role with least-privilege inline policy (IAM management + STS)
- `AmazonSSMManagedInstanceCore` managed policy attached
- Security group: port 22 open for SSH (SSM blocked by org SCP)
- Userdata: installs Java 21, Terraform, Trivy (via RPM repo), Jenkins

```bash
cd infrastructure
terraform init
terraform apply -var="profile=itpu" -var="key_name=jenkins-key"
```

Outputs:
```
jenkins_instance_id = "i-0560474c11ab5a6b9"
jenkins_public_dns  = "ec2-13-51-36-10.eu-north-1.compute.amazonaws.com"
jenkins_ami_used    = "ami-0c4499584c001b49c"
```

### 3.2 Jenkins Setup

SSH tunnel for UI access:
```bash
ssh -i ~/Downloads/jenkins-key.pem \
  -L 8080:localhost:8080 \
  ec2-user@ec2-13-51-36-10.eu-north-1.compute.amazonaws.com
```

Accessed `http://localhost:8080`, completed setup wizard, installed suggested plugins, created admin user.

### 3.3 Pipeline Job Creation

4 jobs created as Pipeline script jobs, each pasting the corresponding Jenkinsfile:

| Job name | Jenkinsfile | State backend path |
|---|---|---|
| `terraform-create` | `Jenkinsfile-create.groovy` | `/var/lib/jenkins/tfstate/terraform-create.tfstate` |
| `terraform-destroy` | `Jenkinsfile-destroy.groovy` | `/var/lib/jenkins/tfstate/terraform-create.tfstate` |
| `terraform-remediate` | `Jenkinsfile-remediate.groovy` | `/var/lib/jenkins/tfstate/terraform-remediated.tfstate` |
| `terraform-cleanup` | `Jenkinsfile-cleanup.groovy` | `/var/lib/jenkins/tfstate/terraform-remediated.tfstate` |

### 3.4 Execution Flow

All 4 jobs run in sequence. Each job's Prepare Workspace stage writes Terraform files inline via heredoc, then initializes Terraform using the shared local backend so state persists between create/destroy pairs.

---

## 4. Security Testing Results

### 4.1 Insecure Configuration (terraform-create)

**Policy:** `ec2:*` on `*` resources — full EC2 access.

Trivy run with `--exit-code 0` (informational, does not block pipeline):

```
Tests: 1 (SUCCESSES: 0, FAILURES: 1)
Failures: 1 (UNKNOWN: 0, LOW: 1, MEDIUM: 0, HIGH: 0, CRITICAL: 0)

AWS-0143 (LOW): One or more policies are attached directly to a user
```

**Observation:** Trivy's IaC checks flag structural misconfigurations (direct user attachment, missing MFA enforcement) rather than policy content wildcards. The `ec2:*` action wildcard is not a Trivy HIGH finding — it is caught by tools like AWS Access Analyzer or Checkov. The LOW finding (`AWS-0143`) still demonstrates Trivy correctly scanning the configuration and identifying a CIS benchmark violation.

### 4.2 Remediated Configuration (terraform-remediate)

**Policy:** 7 specific actions — `ec2:DescribeInstances`, `ec2:DescribeInstanceStatus`, `ec2:DescribeTags`, `ec2:DescribeImages`, `ec2:DescribeVolumes`, `ec2:StartInstances`, `ec2:StopInstances`.

Trivy run with `--exit-code 1 --severity HIGH,CRITICAL` (blocks pipeline on HIGH/CRITICAL):

```
Failures: 1 (UNKNOWN: 0, LOW: 1, MEDIUM: 0, HIGH: 0, CRITICAL: 0)
```

HIGH/CRITICAL enforcement gate:
```
Report Summary: main.tf — 0 misconfigurations
```

**Result:** Gate passed. Pipeline proceeded to `terraform apply`. The same LOW finding (`AWS-0143`) remains because the structural pattern (user attachment) is unchanged — this is acceptable for this lab's scope.

---

## 5. Validation Results

```bash
# After terraform-create — user and insecure policy exist
aws iam get-user --user-name ci-terra-user --profile itpu
aws iam get-policy-version \
  --policy-arn arn:aws:iam::562123137719:policy/ci-terra-ec2-full \
  --version-id v1 --profile itpu

# After terraform-destroy — user gone
aws iam get-user --user-name ci-terra-user --profile itpu
# → NoSuchEntityException ✓

# After terraform-remediate — limited policy exists
aws iam get-policy-version \
  --policy-arn arn:aws:iam::562123137719:policy/ci-terra-ec2-limited \
  --version-id v1 --profile itpu

# After terraform-cleanup — everything gone
aws iam get-user --user-name ci-terra-user --profile itpu
# → NoSuchEntityException ✓
aws iam list-policies --scope Local --profile itpu | grep ci-terra
# → no output ✓
```

---

## 6. Troubleshooting & Lessons Learned

**Issue 1 — Wrong AWS profile during infrastructure deploy**

Terraform ran with the `esimeta-lambda-github-actions` IAM user (no EC2 permissions) instead of the `itpu` profile, causing `403 UnauthorizedOperation` on `DescribeImages` and `DescribeVpcAttribute`.

*Resolution:* Passed `-var="profile=itpu"` explicitly. The `profile` variable defaults to empty (correct for EC2 instance role on Jenkins) but must be set for local Terraform runs.

**Issue 2 — `terraform-destroy` failed: missing `iam:DeleteLoginProfile`**

Terraform's `force_destroy = true` on `aws_iam_user` always calls `DeleteLoginProfile` during destroy, even when no login profile exists. The Jenkins role lacked this permission, so the API returned `AccessDenied` instead of the expected `NoSuchEntity`, causing the destroy to fail after partially completing (policy deleted, user not deleted).

*Resolution:* Added `iam:DeleteLoginProfile` to the Jenkins role inline policy, re-applied infrastructure, re-ran destroy successfully.

**Issue 3 — Terraform state lost between pipeline runs (from PT3)**

Each Jenkins job creates a fresh workspace directory. Without a configured backend, `.tfstate` is written inside the workspace and lost when the next job starts. The destroy job would find no resources to destroy.

*Resolution:* Added `backend "local" { path = "/absolute/path" }` to each Terraform configuration inside the Jenkinsfiles. The `terraform-create` and `terraform-destroy` jobs share `/var/lib/jenkins/tfstate/terraform-create.tfstate`; the `terraform-remediate` and `terraform-cleanup` jobs share `terraform-remediated.tfstate`. The directory is created in userdata (`mkdir -p /var/lib/jenkins/tfstate`) and each Prepare Workspace stage also ensures it exists.

---

## 7. Conclusion & Recommendations

The pipeline successfully demonstrated automated IAM provisioning with integrated security scanning. Trivy detected the `AWS-0143` CIS violation in both configurations and correctly passed the HIGH/CRITICAL enforcement gate for the remediated version.

**Key finding:** Trivy's default IaC ruleset checks structural patterns (attachment method, MFA enforcement, resource tagging) rather than policy content wildcards. For complete IAM policy analysis, Trivy should be combined with AWS Access Analyzer or Checkov.

**Recommendations for production:**
1. Use S3 remote backend with DynamoDB state locking instead of local file backend
2. Add Checkov alongside Trivy to catch overly-permissive action wildcards (`ec2:*`)
3. Add a manual approval stage between Plan and Apply
4. Restrict SSH CIDR to corporate VPN instead of `0.0.0.0/0`
5. Pin Terraform provider versions in all pipeline configurations

---

## 8. Appendix

**Jenkins instance:**
```
Instance ID: i-0560474c11ab5a6b9
Public DNS:  ec2-13-51-36-10.eu-north-1.compute.amazonaws.com
AMI:         ami-0c4499584c001b49c (Amazon Linux 2023, eu-north-1)
Trivy:       0.71.2
```

**IAM resources created/destroyed:**
```
Insecure:
  User:   arn:aws:iam::562123137719:user/ci-terra-user
  Policy: arn:aws:iam::562123137719:policy/ci-terra-ec2-full

Remediated:
  User:   arn:aws:iam::562123137719:user/ci-terra-user
  Policy: arn:aws:iam::562123137719:policy/ci-terra-ec2-limited
```

**Full Terraform and Jenkinsfile code:** see `infrastructure/` and `pipelines/` directories.
