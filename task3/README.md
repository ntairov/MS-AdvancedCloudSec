# Task 3 — Jenkins CI/CD Pipeline for IAM Policy Automation

Jenkins controller on EC2 (accessed via SSM) runs Terraform to deploy a least-privilege IAM policy.

## Architecture

```
Local machine
    │
    │  SSM port-forward (no SSH, no open ports)
    ▼
EC2 Jenkins (eu-north-1)
    │  Instance role (no static keys)
    ▼
Terraform → IAM user + least-privilege EC2 policy
```

## Step 1 — Deploy Jenkins infrastructure

```bash
cd infrastructure
cp terraform.tfvars.example terraform.tfvars   # adjust if needed
terraform init
terraform plan -out=tfplan
terraform apply tfplan
```

Note the `jenkins_instance_id` output.

## Step 2 — Wait for Jenkins to start (~3 minutes)

Jenkins is installed via userdata. Check it's running:

```bash
aws ssm send-command \
  --instance-ids <jenkins_instance_id> \
  --document-name "AWS-RunShellScript" \
  --parameters '{"commands":["systemctl is-active jenkins"]}' \
  --profile itpu --region eu-north-1 \
  --query 'Command.CommandId' --output text
```

Wait ~10 seconds, then get the output:

```bash
aws ssm get-command-invocation \
  --command-id <command_id> \
  --instance-id <jenkins_instance_id> \
  --profile itpu --region eu-north-1 \
  --query 'StandardOutputContent' --output text
```

Should print `active`.

## Step 3 — Get Jenkins initial admin password

```bash
aws ssm send-command \
  --instance-ids <jenkins_instance_id> \
  --document-name "AWS-RunShellScript" \
  --parameters '{"commands":["cat /var/lib/jenkins/secrets/initialAdminPassword"]}' \
  --profile itpu --region eu-north-1 \
  --query 'Command.CommandId' --output text
```

Then retrieve:

```bash
aws ssm get-command-invocation \
  --command-id <command_id> \
  --instance-id <jenkins_instance_id> \
  --profile itpu --region eu-north-1 \
  --query 'StandardOutputContent' --output text
```

## Step 4 — Open Jenkins UI via SSM port-forward

```bash
aws ssm start-session \
  --target <jenkins_instance_id> \
  --document-name AWS-StartPortForwardingSession \
  --parameters '{"portNumber":["8080"],"localPortNumber":["8080"]}' \
  --profile itpu \
  --region eu-north-1
```

Keep this terminal open. Open http://localhost:8080 in your browser.

## Step 5 — Configure Jenkins

1. Enter initial admin password
2. Install suggested plugins
3. Create admin user
4. Go to **Manage Jenkins → Plugins** → install: **Pipeline**
5. Go to **Manage Jenkins → Tools** → add Terraform installation:
   - Name: `terraform`
   - Install directory: `/usr/bin`

## Step 6 — Create pipeline jobs

**Job 1: deploy-hardened-policy**
- New Item → Pipeline
- Pipeline Definition: Pipeline script
- Paste contents of `pipelines/Jenkinsfiles/Jenkinsfile-deploy.groovy`

**Job 2: destroy-hardened-policy**
- New Item → Pipeline
- Pipeline Definition: Pipeline script
- Paste contents of `pipelines/Jenkinsfiles/Jenkinsfile-destroy.groovy`

## Step 7 — Run deploy pipeline

Click **Build Now** on `deploy-hardened-policy`. Watch the console output.

## Step 8 — Verify IAM resources

```bash
ACCOUNT_ID=$(aws sts get-caller-identity --profile itpu --query Account --output text)

aws iam get-user --user-name ci-policy-user --profile itpu
aws iam list-attached-user-policies --user-name ci-policy-user --profile itpu
aws iam get-policy \
  --policy-arn arn:aws:iam::${ACCOUNT_ID}:policy/ci-ec2-controlled-access \
  --profile itpu
aws iam get-policy-version \
  --policy-arn arn:aws:iam::${ACCOUNT_ID}:policy/ci-ec2-controlled-access \
  --version-id v1 --profile itpu
```

## Step 9 — Run destroy pipeline

Click **Build Now** on `destroy-hardened-policy`. Confirm deletion:

```bash
aws iam get-user --user-name ci-policy-user --profile itpu
# Expected: NoSuchEntityException
```

## Step 10 — Destroy Jenkins infrastructure

```bash
cd infrastructure
terraform destroy -auto-approve
```

## Policy: why it is least-privilege

| Permission | Scope | Reason |
|---|---|---|
| `ec2:Describe*` | `*` (read-only, no resource scope possible) | Required for inventory; no mutation risk |
| `ec2:StartInstances` | Account + region + tag `Environment=controlled` | Prevents starting arbitrary instances |
| `ec2:StopInstances` | Account + region + tag `Environment=controlled` | Same tag constraint |

No wildcard `*` actions. No IAM, S3, or other service access granted.
