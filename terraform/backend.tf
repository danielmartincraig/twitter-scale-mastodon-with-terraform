terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
  cloud {
    organization = "twitter-scale-mastodon-with-terraform"
    workspaces {
      name = "twitter-scale-mastodon-with-terraform-workspace"
    }
  }
  required_version = ">= 1.5.0"
}
