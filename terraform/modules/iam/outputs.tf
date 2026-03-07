# IAM module outputs

output "instance_profile_name" {
  value       = aws_iam_instance_profile.ec2_profile.name
  description = "IAM instance profile name for EC2 instances"
}

output "instance_profile_arn" {
  value       = aws_iam_instance_profile.ec2_profile.arn
  description = "IAM instance profile ARN"
}

output "role_arn" {
  value       = aws_iam_role.ec2_role.arn
  description = "IAM role ARN"
}

output "role_name" {
  value       = aws_iam_role.ec2_role.name
  description = "IAM role name"
}
