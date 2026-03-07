# IAM module for EC2 instance permissions
# Validates: Requirements 3.6, 10.3, 10.6

# IAM role for EC2 instances
resource "aws_iam_role" "ec2_role" {
  name = "mastodon-ec2-role-${var.environment}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name        = "mastodon-ec2-role-${var.environment}"
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

# S3 access policy for media storage and deployment artifacts
resource "aws_iam_policy" "s3_access" {
  name        = "mastodon-s3-access-${var.environment}"
  description = "Allows EC2 instances to access S3 for media storage and deployment"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket"
        ]
        Resource = [
          "arn:aws:s3:::mastodon-media-${var.environment}",
          "arn:aws:s3:::mastodon-media-${var.environment}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:ListBucket"
        ]
        Resource = [
          "arn:aws:s3:::${var.deploy_bucket}",
          "arn:aws:s3:::${var.deploy_bucket}/*"
        ]
      }
    ]
  })

  tags = {
    Name        = "mastodon-s3-access-${var.environment}"
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

# CloudWatch Logs policy
resource "aws_iam_policy" "cloudwatch_logs" {
  name        = "mastodon-cloudwatch-logs-${var.environment}"
  description = "Allows EC2 instances to write logs to CloudWatch"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogStreams"
        ]
        Resource = [
          "arn:aws:logs:*:*:log-group:/aws/ec2/mastodon/*",
          "arn:aws:logs:*:*:log-group:/aws/mastodon/${var.environment}/*"
        ]
      }
    ]
  })

  tags = {
    Name        = "mastodon-cloudwatch-logs-${var.environment}"
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

# Systems Manager policy
resource "aws_iam_policy" "systems_manager" {
  name        = "mastodon-systems-manager-${var.environment}"
  description = "Allows EC2 instances to use Systems Manager"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ssm:GetParameter",
          "ssm:GetParameters",
          "ssm:GetParametersByPath",
          "ssm:DescribeParameters"
        ]
        Resource = "arn:aws:ssm:*:*:parameter/mastodon/${var.environment}/*"
      },
      {
        Effect = "Allow"
        Action = [
          "ssm:UpdateInstanceInformation",
          "ssmmessages:CreateControlChannel",
          "ssmmessages:CreateDataChannel",
          "ssmmessages:OpenControlChannel",
          "ssmmessages:OpenDataChannel"
        ]
        Resource = "*"
      }
    ]
  })

  tags = {
    Name        = "mastodon-systems-manager-${var.environment}"
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

# Attach policies to the role
resource "aws_iam_role_policy_attachment" "s3_access" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = aws_iam_policy.s3_access.arn
}

resource "aws_iam_role_policy_attachment" "cloudwatch_logs" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = aws_iam_policy.cloudwatch_logs.arn
}

resource "aws_iam_role_policy_attachment" "systems_manager" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = aws_iam_policy.systems_manager.arn
}

# AWS managed policy required for SSM Session Manager and Run Command
resource "aws_iam_role_policy_attachment" "ssm_managed_instance_core" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# Instance profile for EC2 attachment
resource "aws_iam_instance_profile" "ec2_profile" {
  name = "mastodon-ec2-profile-${var.environment}"
  role = aws_iam_role.ec2_role.name

  tags = {
    Name        = "mastodon-ec2-profile-${var.environment}"
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}
