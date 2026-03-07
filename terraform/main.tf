# Configure AWS provider
provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "terraform"
    }
  }
}

# VPC and networking module
module "vpc" {
  source = "./modules/vpc"

  environment = var.environment
  vpc_cidr    = var.vpc_cidr
  aws_region  = var.aws_region
}

# Security groups module
module "security_groups" {
  source = "./modules/security-groups"

  environment = var.environment
  vpc_id      = module.vpc.vpc_id
  vpc_cidr    = var.vpc_cidr
}

# IAM roles and instance profiles module
module "iam" {
  source = "./modules/iam"

  environment   = var.environment
  deploy_bucket = var.deploy_bucket
}

module "backend-service" {
  source = "./modules/backend-service"

  instance_count              = var.instance_count
  environment                 = var.environment
  instance_type               = var.backend_service_instance_type
  subnet_ids                  = module.vpc.public_subnet_ids
  security_group_ids          = [module.security_groups.api_sg_id]
  iam_instance_profile        = module.iam.instance_profile_name
  ssh_key_name                = var.ssh_key_name
  root_volume_size            = var.root_volume_size
  enable_detailed_monitoring  = var.enable_detailed_monitoring
  deploy_bucket               = var.deploy_bucket
  rama_s3_key                 = var.rama_s3_key
  aws_region                  = var.aws_region
  git_sha                     = var.git_sha
}
