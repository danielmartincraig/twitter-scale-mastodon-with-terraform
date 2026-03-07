# Security groups module outputs

output "zookeeper_sg_id" {
  value       = aws_security_group.zookeeper.id
  description = "Security group ID for Zookeeper cluster"
}

output "api_sg_id" {
  value       = aws_security_group.api.id
  description = "Security group ID for API instances"
}
