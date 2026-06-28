output "jenkins_instance_id" {
  value = aws_instance.jenkins.id
}

output "jenkins_public_dns" {
  value = aws_instance.jenkins.public_dns
}

output "jenkins_role_name" {
  value = aws_iam_role.jenkins_role.name
}

output "jenkins_security_group_id" {
  value = aws_security_group.jenkins_sg.id
}

output "jenkins_ami_used" {
  value = data.aws_ami.al2023.id
}
