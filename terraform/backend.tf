terraform {
  backend "s3" {
    bucket         = "devops-app2-tfstate-364077344467"
    key            = "devops-app2/terraform.tfstate"
    region         = "us-east-2"
    dynamodb_table = "devops-app2-tf-lock"
    encrypt        = true

  }
}