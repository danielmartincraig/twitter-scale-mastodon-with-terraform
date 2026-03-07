# Zookeeper module outputs

output "instance_ids" {
  value       = aws_instance.zookeeper[*].id
  description = "Instance IDs of backend service nodes"
}

output "private_ips" {
  value       = aws_instance.zookeeper[*].private_ip
  description = "Private IP addresses of backend service nodes"
}

output "public_ips" {
  value       = aws_instance.zookeeper[*].public_ip
  description = "Public IP addresses of backend service nodes"
}
