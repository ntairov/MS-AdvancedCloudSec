output "jenkins_instance_id" {
  value       = aws_instance.jenkins.id
  description = "Instance ID — used in SSM start-session commands."
}

output "jenkins_public_dns" {
  value       = aws_instance.jenkins.public_dns
  description = "Public DNS (for reference; access is via SSM port-forward)."
}

output "jenkins_ami_used" {
  value       = data.aws_ami.al2023.id
  description = "AMI resolved at apply time."
}

output "jenkins_role_name" {
  value       = aws_iam_role.jenkins_role.name
  description = "IAM role attached to the Jenkins instance."
}

output "jenkins_security_group_id" {
  value       = aws_security_group.jenkins_sg.id
  description = "Security group ID."
}
