variable "region" {
  description = "AWS region for deployment."
  type        = string
  default     = "eu-north-1"
}

variable "profile" {
  description = "AWS CLI profile name."
  type        = string
  default     = "itpu"
}

variable "instance_type" {
  description = "EC2 instance type for Jenkins server."
  type        = string
  default     = "t3.medium"
}

variable "key_name" {
  description = "Existing AWS key pair name (leave empty to disable SSH)."
  type        = string
  default     = ""
}

variable "allowed_ssh_cidr" {
  description = "CIDR block allowed to SSH (only used when key_name is set)."
  type        = string
  default     = "0.0.0.0/0"
}

variable "project_tag" {
  description = "Tag applied to all resources."
  type        = string
  default     = "ci-cd-security-homework"
}
