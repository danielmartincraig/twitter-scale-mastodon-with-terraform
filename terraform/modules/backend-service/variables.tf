# Zookeeper module variables

variable "environment" {
  type        = string
  description = "Deployment environment"
}

variable "instance_count" {
  type        = number
  description = "Number of Zookeeper instances"
}

variable "instance_type" {
  type        = string
  description = "EC2 instance type"
}

variable "subnet_ids" {
  type        = list(string)
  description = "Subnet IDs for Zookeeper instances"
}

variable "security_group_ids" {
  type        = list(string)
  description = "Security group IDs to attach to instances"
}

variable "iam_instance_profile" {
  type        = string
  description = "IAM instance profile name"
}

variable "ssh_key_name" {
  type        = string
  description = "SSH key pair name"
}

variable "root_volume_size" {
  type        = number
  description = "Root volume size in GB"
}

variable "enable_detailed_monitoring" {
  type        = bool
  description = "Enable detailed CloudWatch monitoring"
}

variable "deploy_bucket" {
  type        = string
  description = "S3 bucket name used for deployment artifacts (Rama runtime, etc.)"
}

variable "rama_s3_key" {
  type        = string
  description = "S3 object key for the Rama runtime archive (e.g. rama/rama-latest.zip)"
}

variable "aws_region" {
  type        = string
  description = "AWS region, passed to aws s3 cp for explicit region targeting"
}

variable "git_sha" {
  type        = string
  description = "Git commit SHA used to locate the application JARs in S3 (jars/backend/<sha>/ and jars/api/<sha>/)"
}
