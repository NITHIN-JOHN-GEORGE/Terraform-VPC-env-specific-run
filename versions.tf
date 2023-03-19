terraform {
  required_version = "~> 1.0"
  # backend "s3" {
  #   bucket = "iam-user-management"
  #   key    = "terraform.tfstate"
  #   region = "us-west-2"
  #   profile = "qa"
  # }
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.54.0"
    }
  }
}

provider "aws" {
  region  = var.region
  access_key = var.AWS_ACCESS_KEY
  secret_key = var.AWS_SECRET_KEY
}

# provider "aws" {
#   region  = "us-east-2"
#   profile = "qa" # you have to give the profile name here. not the variable("${var.AWS_PROFILE}")
# }
