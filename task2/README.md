# Task 2 — AWS SIEM: IAM DeleteUser Anomaly Detection

CloudTrail → CloudWatch Logs → Kinesis Firehose → OpenSearch  
EventBridge rule → SNS email alert on `DeleteUser` API call

## Stack

| Component | Purpose |
|---|---|
| S3 | CloudTrail log archive |
| CloudTrail | Account-level management events (all regions) |
| CloudWatch Logs | Real-time log stream |
| Kinesis Firehose | Deliver logs to OpenSearch |
| OpenSearch | SIEM analytics & dashboards |
| EventBridge | Pattern match `DeleteUser` event |
| SNS | Email alert to security team |
| CloudWatch Alarm | Secondary detection signal |

## Setup

```bash
cp terraform.tfvars.example terraform.tfvars
# edit terraform.tfvars with your values

terraform init
terraform fmt && terraform validate
terraform plan
terraform apply    # OpenSearch takes ~15 min
```

After apply, check your email for the SNS subscription confirmation — **click the link before triggering the test event**.

## OpenSearch — Firehose role mapping (required for log indexing)

With fine-grained access control enabled, the Firehose IAM role must be mapped to an OpenSearch backend role:

1. Open `https://<opensearch_endpoint>/_dashboards`
2. Log in with `opensearch_master_username` / `opensearch_master_password`
3. Go to **Security → Roles → all_access → Mapped users → Manage mapping**
4. Add the Firehose IAM role ARN (shown in `terraform output`)
5. Save

This step is required only for OpenSearch log indexing. The EventBridge → SNS email alert works independently.

## Test the detection

```bash
# Create a privileged IAM user
aws iam create-user --user-name SIEMLabTargetUser \
  --tags Key=Role,Value=Privileged Key=Owner,Value=SIEMLab \
  --profile itpu

aws iam attach-user-policy --user-name SIEMLabTargetUser \
  --policy-arn arn:aws:iam::aws:policy/AdministratorAccess \
  --profile itpu

# Trigger detection
aws iam detach-user-policy --user-name SIEMLabTargetUser \
  --policy-arn arn:aws:iam::aws:policy/AdministratorAccess \
  --profile itpu

aws iam delete-user --user-name SIEMLabTargetUser --profile itpu
```

Check email inbox for SNS alert (may take 1-2 minutes).

## Verify evidence

- **CloudWatch Alarm**: `${project_prefix}-DeleteUserAlarm` → ALARM state
- **CloudTrail/OpenSearch**: search `eventName.keyword: "DeleteUser"`
- **Email alert**: screenshot subject + timestamp

## Cleanup

```bash
terraform destroy
```
