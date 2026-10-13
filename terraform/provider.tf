terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 4.0"
    }

    random = {
      source  = "hashicorp/random"
      version = "~>3.0"
    }
  }
}

#42 we use this region for all of our aws resources and services
provider "aws" {
  region = "us-east-2"
}


#42 We added this ALIAS now, is only used by resources 
# that ask for it with provider = aws.us_east_1, which in your project is just the WAF.
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"
}


provider "cloudflare" {
  api_token = var.cloudflare_api_token
}

