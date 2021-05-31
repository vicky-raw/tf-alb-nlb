provider "aws" {
  region = "us-east-1"
  allowed_account_ids = ["----------AWS_ACCOUNT_ID------------"]
}

module "alb_nlb" {
    source = "./alb_nlb_module"
    vpc_id = "vpc-29c5064f"
    subnet_names = ["staging-1a","staging-1b"]
    #alb_dns_name = "Add ALB DNS Name"
    #log_bucket_name = "Add log bucket name"
}