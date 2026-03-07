# Core Terraform variables for GitLab Terraform EC2 Deployment
# Validates: Requirements 3.8

variable "environment" {
  type        = string
  description = "Deployment environment (staging/production)"

  validation {
    condition     = contains(["staging", "production"], var.environment)
    error_message = "Environment must be either 'staging' or 'production'."
  }
}

variable "aws_region" {
  type        = string
  description = "AWS region for resource deployment"
  default     = "us-east-1"
}

variable "backend_service_instance_type" {
  type        = string
  description = "EC2 instance type for backend service instances running Zookeeper + Rama conductor + Rama supervisor"
  default     = "t4g.large"

  validation {
    condition     = can(regex("^t4g\\.", var.backend_service_instance_type))
    error_message = "Backend service instance type must be a t4g family instance (e.g. t4g.large, t4g.xlarge)."
  }
}

variable "instance_count" {
  type        = number
  description = "Number of backend service nodes in the cluster (must be odd number for quorum)"
  default     = 1

  validation {
    condition     = var.instance_count >= 1 && var.instance_count % 2 == 1
    error_message = "Backend service count must be an odd number >= 1 for proper quorum."
  }
}

variable "ssh_key_name" {
  type        = string
  description = "AWS EC2 key pair name for SSH access to instances"
}

variable "vpc_cidr" {
  type        = string
  description = "CIDR block for the VPC"
  default     = "10.0.0.0/16"
}

variable "enable_detailed_monitoring" {
  type        = bool
  description = "Enable detailed CloudWatch monitoring for EC2 instances (increases cost)"
  default     = false
}

variable "root_volume_size" {
  type        = number
  description = "Root volume size in GB for EC2 instances"
  default     = 20

  validation {
    condition     = var.root_volume_size >= 20
    error_message = "Root volume size must be at least 20GB for JAR files and logs."
  }
}

variable "project_name" {
  type        = string
  description = "Project name for resource tagging"
  default     = "mastodon"
}

variable "deploy_bucket" {
  type        = string
  description = "S3 bucket name used for staging deployment artifacts (must already exist)"
}

variable "rama_s3_key" {
  type        = string
  description = "S3 object key for the Rama runtime archive within the deploy bucket (e.g. rama/rama-latest.zip)"
}

variable "git_sha" {
  type        = string
  description = "Git commit SHA identifying which application JARs to download from S3 on instance boot"
}
