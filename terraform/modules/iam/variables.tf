# IAM module variables

variable "environment" {
  type        = string
  description = "Deployment environment"
}

variable "deploy_bucket" {
  type        = string
  description = "S3 bucket name used for staging deployment artifacts"
}
