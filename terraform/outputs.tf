# Terraform outputs for deployment information
# Validates: Requirements 5.4, 15.1, 15.2, 15.3, 15.4

output "vpc_id" {
  value       = module.vpc.vpc_id
  description = "ID of the VPC"
}

output "zookeeper_instance_ids" {
  value       = module.backend-service.instance_ids
  description = "Instance IDs of Zookeeper nodes"
}

output "zookeeper_private_ips" {
  value       = module.backend-service.private_ips
  description = "Private IP addresses of Zookeeper nodes"
}

output "zookeeper_public_ips" {
  value       = module.backend-service.public_ips
  description = "Public IP addresses of Zookeeper nodes (if in public subnet)"
}

output "security_group_ids" {
  value = {
    zookeeper = module.security_groups.zookeeper_sg_id
    api       = module.security_groups.api_sg_id
  }
  description = "Security group IDs for all components"
}

output "iam_instance_profile_name" {
  value       = module.iam.instance_profile_name
  description = "IAM instance profile name for EC2 instances"
}
