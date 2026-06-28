variable "region" {
  description = "AWS region for deployment."
  type        = string
  default     = "eu-north-1"
}

variable "instance_type" {
  description = "EC2 instance type for Jenkins server."
  type        = string
  default     = "t3.medium"
}

variable "key_name" {
  description = "Existing AWS key pair name (required — SSM is blocked by org SCP)."
  type        = string
  default     = ""
}

variable "allowed_ssh_cidr" {
  description = "CIDR block allowed to SSH."
  type        = string
  default     = "0.0.0.0/0"
}

variable "project_tag" {
  description = "Tag prefix for all resources."
  type        = string
  default     = "ci-cd-security-homework"
}

variable "profile" {
  description = "AWS CLI profile for local execution (leave empty for EC2 instance role)."
  type        = string
  default     = ""
}
