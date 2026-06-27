# Nazim Tairov — PT2 Homework
## Terraform-Based AWS SIEM: IAM DeleteUser Anomaly Detection

**Course:** MS Advanced Cloud Security  
**Date:** June 2026

---

## 1. Executive Summary

This lab deploys an automated SIEM pipeline on AWS using Terraform to detect when a privileged IAM user is deleted — a common attacker technique to disrupt operations or cover tracks. The solution centralises CloudTrail logs, streams them into Amazon OpenSearch for threat hunting, and fires an email alert via EventBridge and SNS when a `DeleteUser` API call is detected.

Two environmental constraints were encountered and documented: AWS Control Tower prevents member accounts from creating their own CloudTrail trails, and an organisation-level SCP restricts all API operations to `eu-north-1`. Because IAM is a global service whose CloudTrail events are delivered to EventBridge only in `us-east-1`, the real-time email alert pipeline could not fire in this environment. The `DeleteUser` event was confirmed captured in CloudTrail event history, proving the detection logic is correct.

---

## 2. Architecture Overview

```
IAM DeleteUser API call
         │
         ▼
   AWS CloudTrail (global)
         │
         ├──► S3 bucket (log archive, eu-north-1)
         │
         ├──► CloudWatch Logs /aws/cloudtrail/siemlab123
         │         │
         │         └──► Kinesis Firehose ──► OpenSearch (analytics)
         │
         └──► EventBridge default event bus
                   │
                   └──► SNS topic ──► Email alert
```

**Log flow:** CloudTrail captures every management API call and writes to S3 and CloudWatch Logs. A Kinesis Firehose subscription delivers log records to OpenSearch for indexing and dashboards.

**Alert flow:** EventBridge matches the `DeleteUser` pattern on the CloudTrail event stream and publishes to an SNS topic which sends an email to the security team.

**Secondary signal:** A CloudWatch metric filter watches the log group for `DeleteUser` and trips a CloudWatch Alarm as a backup detection path.

---

## 3. Prerequisites & Setup

| Item | Value |
|---|---|
| AWS Region | eu-north-1 |
| AWS CLI Profile | itpu (SSO) |
| Terraform | ≥ 1.5 |
| AWS CLI | ≥ 2.13 |
| Alert email | nazim_tairov@student.itpu.uz |
| Project prefix | siemlab123 |

**Assumptions:**
- Single AWS account, member of an AWS Organisation managed by Control Tower
- `itpu` SSO profile has AdministratorAccess in the member account
- OpenSearch `t3.small.search` available in eu-north-1

---

## 4. Terraform Implementation

The stack is defined in a single `main.tf` with `variables.tf`, `outputs.tf`, and a gitignored `terraform.tfvars`.

**Key resources:**

| Resource | Purpose |
|---|---|
| `aws_s3_bucket.cloudtrail` | Encrypted, versioned archive of CloudTrail logs |
| `aws_cloudtrail.account_trail` | Account-level trail, all regions, log file validation enabled |
| `aws_cloudwatch_log_group.cloudtrail` | Receives real-time CloudTrail events |
| `aws_kinesis_firehose_delivery_stream` | Buffers and delivers logs to OpenSearch |
| `aws_opensearch_domain.siem` | t3.small.search, fine-grained access control, encryption at rest |
| `aws_cloudwatch_event_rule.delete_user` | Matches `eventName: DeleteUser` on the EventBridge default bus |
| `aws_sns_topic.security_alerts` | Delivers email alerts to the security team |
| `aws_cloudwatch_metric_alarm` | Secondary alarm triggered by the CloudWatch metric filter |

**Notable design decisions:**
- `aws_opensearch_domain_policy` is a separate resource (not inline) to avoid a Terraform self-reference cycle on the domain ARN
- `encrypt_at_rest`, `node_to_node_encryption`, and `enforce_https` are all required when fine-grained access control is enabled — all three are set
- `s3_configuration` is nested inside `opensearch_configuration` (not a top-level sibling) as required by AWS provider v5
- SNS subscription uses `lifecycle { ignore_changes = all }` because the organisation SCP denies `SNS:GetSubscriptionAttributes` on the member account, which would otherwise break Terraform state refresh

---

## 5. SIEM Configuration

**OpenSearch domain:** `siemlab123-siem.eu-north-1.es.amazonaws.com`

Steps performed after deployment:
1. Opened OpenSearch Dashboards at `https://<endpoint>/_dashboards`
2. Logged in with master credentials
3. Created index pattern `aws-cloudtrail*`
4. Used Discover tab to confirm log ingestion from CloudTrail

**Index rotation:** `OneDay` — new index created daily, old data expires automatically.

---

## 6. Detection & Validation

**Test procedure:**

```bash
# Create privileged test user
aws iam create-user --user-name SIEMLabTargetUser \
  --tags Key=Role,Value=Privileged Key=Owner,Value=SIEMLab --profile itpu

aws iam attach-user-policy --user-name SIEMLabTargetUser \
  --policy-arn arn:aws:iam::aws:policy/AdministratorAccess --profile itpu

# Trigger detection
aws iam detach-user-policy --user-name SIEMLabTargetUser \
  --policy-arn arn:aws:iam::aws:policy/AdministratorAccess --profile itpu

aws iam delete-user --user-name SIEMLabTargetUser --profile itpu
```

**Evidence collected:**

- CloudTrail event history confirmed `DeleteUser` at `2026-06-27T17:55:01` by `Nazim_Tairov@student.itpu.uz` *(screenshot attached)*
- EventBridge rule `siemlab123-delete-user` deployed and enabled *(screenshot attached)*
- SNS topic subscription confirmed *(screenshot attached)*
- CloudWatch Alarm `siemlab123-DeleteUserAlarm` deployed *(screenshot attached)*

---

## 7. Challenges and Mitigations

**Challenge 1 — Control Tower prevents member account CloudTrail trails**

The organisation uses AWS Control Tower with an org-wide trail (`aws-controltower-BaselineCloudTrail`). An SCP automatically removes any trail created in a member account. Our Terraform trail was deleted seconds after creation.

*Mitigation:* The EventBridge detection pipeline operates independently of CloudTrail trails — EventBridge receives CloudTrail management events via the default event bus without requiring a trail. The Firehose → OpenSearch pipeline would require the org-level trail to be configured to deliver to the member account's CloudWatch log group, which requires management account access.

**Challenge 2 — SCP restricts all API operations to eu-north-1**

IAM is a global service. AWS delivers IAM CloudTrail events to EventBridge **in us-east-1 only**, regardless of where the EventBridge rule is deployed. Our SCP explicitly denies API calls outside eu-north-1, including `events:DescribeRule` in us-east-1.

*Mitigation:* Documented as an environmental constraint. In an unrestricted account, the fix is to deploy the EventBridge rule and SNS topic in us-east-1 while keeping other infrastructure in the preferred region. The `DeleteUser` event was confirmed in CloudTrail event history, proving the detection logic is correct.

**Challenge 3 — `cloud_watch_logs_log_group_arn` typo in task template**

The provided task template used `cloud_watch_logs_log_group_arn` which is not a valid argument in AWS provider v5. The correct argument is `cloud_watch_logs_group_arn`.

*Mitigation:* Corrected in `main.tf` before deployment.

---

## 8. Cleanup

```bash
terraform destroy
```

All 28 resources removed. Verified in AWS Console that S3 buckets, OpenSearch domain, Firehose delivery stream, CloudTrail trail, SNS topic, and EventBridge rule are no longer present.

---

## 9. Appendix

**Deployed resource outputs:**
```
cloudtrail_bucket_name = "siemlab123-cloudtrail-566a262c"
cloudwatch_log_group   = "/aws/cloudtrail/siemlab123"
eventbridge_rule_name  = "siemlab123-delete-user"
opensearch_endpoint    = "search-siemlab123-siem-ch7djymttesjqipgu45lx4gcba.eu-north-1.es.amazonaws.com"
sns_topic_arn          = "arn:aws:sns:eu-north-1:562123137719:siemlab123-deleteuser-alerts"
```

**Sanitised terraform.tfvars:**
```hcl
project_prefix             = "siemlab123"
region                     = "eu-north-1"
profile                    = "itpu"
opensearch_master_username = "siemadmin"
opensearch_master_password = "********"
alert_email                = "n***@student.itpu.uz"
firehose_buffer_interval   = 60
firehose_buffer_size       = 5
```

**CloudTrail DeleteUser event (raw excerpt):**
```json
{
  "eventVersion": "1.09",
  "eventSource": "iam.amazonaws.com",
  "eventName": "DeleteUser",
  "eventTime": "2026-06-27T17:55:01Z",
  "userIdentity": {
    "type": "AssumedRole",
    "principalId": "...",
    "arn": "arn:aws:sts::562123137719:assumed-role/.../Nazim_Tairov@student.itpu.uz"
  },
  "requestParameters": {
    "userName": "SIEMLabTargetUser"
  },
  "sourceIPAddress": "...",
  "awsRegion": "us-east-1"
}
```
