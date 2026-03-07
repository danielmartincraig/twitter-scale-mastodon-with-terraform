# VPC module outputs

output "vpc_id" {
  value       = aws_vpc.main.id
  description = "ID of the VPC"
}

output "public_subnet_ids" {
  value       = [aws_subnet.public.id]
  description = "IDs of public subnets"
}

output "private_subnet_ids" {
  value       = [aws_subnet.private.id]
  description = "IDs of private subnets"
}

output "vpc_cidr_block" {
  value       = aws_vpc.main.cidr_block
  description = "CIDR block of the VPC"
}

output "public_subnet_cidr" {
  value       = aws_subnet.public.cidr_block
  description = "CIDR block of the public subnet"
}

output "private_subnet_cidr" {
  value       = aws_subnet.private.cidr_block
  description = "CIDR block of the private subnet"
}

output "nat_gateway_id" {
  value       = aws_nat_gateway.main.id
  description = "ID of the NAT gateway"
}

output "internet_gateway_id" {
  value       = aws_internet_gateway.main.id
  description = "ID of the internet gateway"
}
