# PaySecure IAM Misconfiguration Detection & Remediation

Automated detection and remediation of overly permissive IAM policies using
AWS Security Hub, EventBridge, CloudWatch, and Terraform.

## Workflow

### Phase 1 — Deploy misconfiguration
```bash
terraform init
terraform apply          # remediated=false by default
```
Wait 10–15 minutes for Security Hub (FSBP) to evaluate and raise findings.

### Verify finding (CLI)
```bash
aws securityhub get-findings \
  --profile itpu \
  --filters '{"ProductName":[{"Value":"Security Hub","Comparison":"EQUALS"}],"ResourceType":[{"Value":"AwsIamPolicy","Comparison":"EQUALS"}],"ComplianceStatus":[{"Value":"FAILED","Comparison":"EQUALS"}]}' \
  --query 'Findings[*].{Title:Title,Severity:Severity.Label,Resource:Resources[0].Id,Status:Compliance.Status}'
```

### Phase 2 — Remediate
```bash
terraform apply -var="remediated=true"
```

### Retrieve access keys (for testing only)
```bash
terraform output -raw access_key_id
terraform output -raw secret_access_key
```

### Cleanup
```bash
terraform destroy
```

## Assumptions
- AWS profile: `itpu`
- Region: `eu-north-1`
- Security Hub may already be enabled from a prior task — Terraform handles this gracefully
- Access keys should be stored in a password manager and rotated/deleted after testing
