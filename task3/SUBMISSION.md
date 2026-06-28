# Nazim Tairov — PT3 Homework
## Automate the Deployment of Security Policies Using Terraform

**Course:** MS Advanced Cloud Security  
**Date:** June 2026

---

## 1. Introduction & Objectives

This lab implements a Jenkins-driven CI/CD pipeline that provisions a hardened IAM user and least-privilege policy via Terraform — all running on an AWS-hosted Jenkins controller with no static credentials. The pipeline demonstrates Infrastructure-as-Code security practices: instance role-based authentication, least-privilege IAM policy with resource tagging conditions, and automated policy lifecycle management.

---

## 2. Architecture & Tools Overview

```
Local machine (SSH tunnel :8080)
        │
        ▼
EC2 t3.medium — Jenkins 2.555 (eu-north-1)
        │  EC2 instance role (no static keys)
        ▼
Terraform (inline in Jenkinsfile)
        │
        ▼
AWS IAM — ci-policy-user + ci-ec2-controlled-access policy
```

**Tools:**

| Tool | Version | Purpose |
|---|---|---|
| Terraform | 1.15.7 | IAM resource provisioning |
| Jenkins | 2.555.3 | CI/CD pipeline orchestration |
| Java | 21 (Amazon Corretto) | Jenkins runtime |
| AWS CLI | 2.33 | Verification commands |
| AWS EC2 (t3.medium) | — | Jenkins host |

**Key security decisions:**
- Jenkins accesses AWS via EC2 instance role — no access keys stored anywhere
- Jenkins UI not exposed publicly — accessed via SSH tunnel only (port 8080 not open in SG)
- IAM policy scoped to account + region + resource tag condition

---

## 3. Implementation Steps

### 3.1 Jenkins Infrastructure Provisioning

Terraform in `infrastructure/` provisions:
- EC2 instance (t3.medium, Amazon Linux 2023, 20GB gp3 volume)
- IAM role with least-privilege inline policy (IAM management + STS only)
- `AmazonSSMManagedInstanceCore` managed policy attached
- Security group: port 22 open for SSH, no public HTTP
- Userdata: installs Java 21, Terraform, AWS CLI, Jenkins

```bash
cd infrastructure
terraform init
terraform plan -out=tfplan
terraform apply tfplan -var="key_name=jenkins-key"
```

Outputs used:
```
jenkins_instance_id = "i-065b2010861476094"
jenkins_public_dns  = "ec2-16-16-123-144.eu-north-1.compute.amazonaws.com"
```

### 3.2 Jenkins Configuration

Connected via SSH tunnel:
```bash
ssh -i ~/Downloads/jenkins-key.pem \
  -L 8080:localhost:8080 \
  ec2-user@ec2-16-16-123-144.eu-north-1.compute.amazonaws.com
```

Accessed `http://localhost:8080`, completed setup wizard, installed suggested plugins, created admin user.

### 3.3 Pipeline Job Setup and Execution

**Job 1: deploy-hardened-policy**
- New Item → Pipeline → Pipeline script
- Pasted `Jenkinsfiles/Jenkinsfile-deploy.groovy`
- Clicked Build Now

Pipeline stages:
1. **Prepare Workspace** — writes Terraform files inline via heredoc
2. **Terraform Init** — downloads AWS provider v5.100.0
3. **Terraform Format & Validate** — confirms code correctness
4. **Terraform Plan** — generates execution plan
5. **Terraform Apply** — creates IAM resources using instance role

Console output confirmed:
```
aws_iam_user.ci_user: Creation complete [id=ci-policy-user]
aws_iam_policy.ec2_limited: Creation complete [id=arn:aws:iam::562123137719:policy/ci-ec2-controlled-access]
aws_iam_user_policy_attachment.attach: Creation complete
Apply complete! Resources: 3 added, 0 changed, 0 destroyed.
Finished: SUCCESS
```

**Job 2: destroy-hardened-policy**
- Same setup with `Jenkinsfiles/Jenkinsfile-destroy.groovy`
- Pipeline ran successfully but reported "No changes" due to absent state file (see Challenges)
- IAM resources cleaned up manually via CLI

---

## 4. Policy Validation Results

```bash
# Confirmed user exists
aws iam get-user --user-name ci-policy-user --profile itpu

# Confirmed policy attached
aws iam list-attached-user-policies --user-name ci-policy-user --profile itpu

# Confirmed policy document
aws iam get-policy-version \
  --policy-arn arn:aws:iam::562123137719:policy/ci-ec2-controlled-access \
  --version-id v1 --profile itpu
```

**Policy structure — why it is least-privilege:**

| Statement | Actions | Resources | Condition |
|---|---|---|---|
| `DescribeOnly` | `ec2:Describe*` (5 actions) | `*` (required — Describe has no resource scope) | None |
| `LifecycleControl` | `ec2:StartInstances`, `ec2:StopInstances` | Account + region ARN only | Tag `Environment=controlled` required |

No wildcards on write actions. No IAM, S3, or cross-service access. The tag condition prevents the user from starting/stopping any instance that isn't explicitly tagged `Environment=controlled`.

---

## 5. Troubleshooting & Lessons Learned

**Issue 1 — SSM Session Manager offline**

Control Tower SCP `p-moclij97` blocks SSM agent registration calls (`ssmmessages:*`, `ec2messages:*`) in member accounts. Despite `AmazonSSMManagedInstanceCore` being attached, the explicit SCP deny overrides IAM permissions.

*Resolution:* Switched to direct SSH with an EC2 key pair.

**Issue 2 — EC2 Instance Connect denied**

The same SCP blocks `ec2-instance-connect:SendSSHPublicKey`.

*Resolution:* Created an EC2 key pair in the console, set `key_name` in Terraform, used direct SSH.

**Issue 3 — Jenkins repo curl missing `-L` flag**

`curl -o` without `-L` doesn't follow HTTP redirects. The Jenkins repo URL redirects, so the downloaded file was an HTML page, not a valid `.repo` file. `dnf` failed with "failed loading jenkins.repo".

*Resolution:* Changed to `curl -fsSL -o` in userdata.

**Issue 4 — Jenkins requires Java 21, Java 17 installed**

Jenkins 2.555+ dropped Java 17 support. Userdata installed `java-17-amazon-corretto` which caused Jenkins to refuse to start.

*Resolution:* Removed Java 17, installed `java-21-amazon-corretto`.

**Issue 5 — Root volume too small (2GB)**

Default EBS root volume was 2GB. After installing Terraform, Java 17, and Jenkins, only 247MB remained — not enough for Java 21 (271MB).

*Resolution:* Expanded EBS volume from 2GB to 10GB via console, then grew the partition and filesystem without stopping the instance:
```bash
sudo growpart /dev/nvme0n1 1
sudo xfs_growfs /
```
Also added `root_block_device { volume_size = 20 }` to Terraform for future deployments.

**Issue 6 — Destroy pipeline found no state**

Each Jenkins pipeline run creates a fresh workspace directory. The deploy and destroy jobs write Terraform files fresh each time with no backend configured, so no `.tfstate` file persists between runs. The destroy job had nothing to destroy.

*Resolution:* Cleaned up IAM resources manually via CLI. In production, the fix is a Terraform S3 remote backend with DynamoDB state locking, shared between both pipeline jobs.

---

## 6. Conclusion & Recommendations

The pipeline successfully automated IAM policy deployment using Terraform executed from Jenkins, authenticated via EC2 instance role. The core security objectives were met: no static credentials, least-privilege policy with tag conditions, and automated lifecycle management.

**Recommendations for production:**
1. Add an S3 remote backend to Terraform so deploy/destroy jobs share state
2. Use Jenkins Shared Libraries instead of inline Terraform heredocs
3. Add a manual approval stage before `terraform apply`
4. Restrict SSH to a specific CIDR (corporate VPN) instead of `0.0.0.0/0`
5. Enable CloudTrail alerts on the Jenkins IAM role to detect misuse

---

## 7. Appendix

**Terraform outputs:**
```
jenkins_instance_id = "i-065b2010861476094"
jenkins_public_dns  = "ec2-16-16-123-144.eu-north-1.compute.amazonaws.com"
jenkins_role_name   = "ci-cd-security-homework-jenkins-role"
iam_user_arn        = "arn:aws:iam::562123137719:user/ci-policy-user"
iam_policy_arn      = "arn:aws:iam::562123137719:policy/ci-ec2-controlled-access"
```

**IAM cleanup commands (after destroy pipeline):**
```bash
ACCOUNT_ID=$(aws sts get-caller-identity --profile itpu --query Account --output text)

aws iam detach-user-policy \
  --user-name ci-policy-user \
  --policy-arn arn:aws:iam::${ACCOUNT_ID}:policy/ci-ec2-controlled-access \
  --profile itpu

aws iam delete-user --user-name ci-policy-user --profile itpu

aws iam delete-policy \
  --policy-arn arn:aws:iam::${ACCOUNT_ID}:policy/ci-ec2-controlled-access \
  --profile itpu
```

**Full Terraform and Jenkinsfile code:** see `infrastructure/` and `pipelines/` directories.
