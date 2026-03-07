# VPC module variables

variable "environment" {
  type        = string
  description = "Deployment environment"
}

variable "vpc_cidr" {
  type        = string
  description = "CIDR block for the VPC"
}

variable "aws_region" {
  type        = string
  description = "AWS region"
}
