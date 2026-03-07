# Staging environment configuration

environment                = "staging"
aws_region                 = "us-east-1"
backend_service_instance_type    = "t4g.xlarge"
instance_count            = 1
vpc_cidr                   = "10.0.0.0/16"
enable_detailed_monitoring = false
root_volume_size           = 60
project_name               = "mastodon"

# S3 key for the Rama runtime archive within the deploy bucket
rama_s3_key                = "rama/rama-latest.zip"

# SSH key name must be set via environment variable or CLI:
# -var="ssh_key_name=your-key-name"

# Allowed SSH CIDRs should be restricted to your IP or bastion:
# -var='allowed_ssh_cidrs=["1.2.3.4/32"]'
