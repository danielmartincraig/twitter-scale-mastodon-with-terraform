# Security Groups Module
# Validates: Requirements 3.3, 3.4, 3.5, 10.7
#
# This module defines security groups for:
# - Zookeeper cluster (ports 2181, 2888, 3888)
# - API instances (port 8080)
# - Rama inter-node communication (ports 3004, 3005)
# - SSH access (port 22, restricted to specific CIDRs)

# Zookeeper Security Group
# Allows Zookeeper client connections (2181) and peer connections (2888, 3888)
resource "aws_security_group" "zookeeper" {
  name        = "${var.environment}-zookeeper-sg"
  description = "Security group for Zookeeper cluster"
  vpc_id      = var.vpc_id

  ingress {
    description     = "Zookeeper client port from API instances"
    from_port       = 2181
    to_port         = 2181
    protocol        = "tcp"
    security_groups = [aws_security_group.api.id]
  }

  ingress {
    description = "Zookeeper peer communication"
    from_port   = 2888
    to_port     = 2888
    protocol    = "tcp"
    self        = true
  }

  ingress {
    description = "Zookeeper leader election"
    from_port   = 3888
    to_port     = 3888
    protocol    = "tcp"
    self        = true
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "${var.environment}-zookeeper-sg"
    Environment = var.environment
    Component   = "zookeeper"
    ManagedBy   = "terraform"
  }
}

# API Security Group
resource "aws_security_group" "api" {
  name        = "${var.environment}-api-sg"
  description = "Security group for API instances"
  vpc_id      = var.vpc_id

  ingress {
    description = "HTTP API port"
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Rama worker port"
    from_port   = 3004
    to_port     = 3004
    protocol    = "tcp"
    self        = true
  }

  ingress {
    description = "Rama client port"
    from_port   = 3005
    to_port     = 3005
    protocol    = "tcp"
    self        = true
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "${var.environment}-api-sg"
    Environment = var.environment
    Component   = "api"
    ManagedBy   = "terraform"
  }
}
