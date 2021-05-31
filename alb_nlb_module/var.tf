variable "vpc_id" {
}

variable "nlb_name" {
  default= "alb-behind-nlb"
}

variable "subnet_names" {
    default = []
}

variable "aws_lb_target_group_name" {
  default = "alb-tg-group"
}

variable "attach_ports_lb" {
  description = "Map from availability zone to the number that should be used for each availability zone's subnet"
  default = {
      /*
    8080 = "i-0b29678a4820741d4"
    8081 = "i-0c5ffb713562e34db"
    8082 = "i-019509200692aa3e8"
    */
  }
}

variable "lambda_role_name" {
  default = "nlb-alb-tg-lambda-role"
}

variable "nlb_inbound_ports" {
  default = [
  {
    from_port = 80
    to_port =   80
    cidr_block = ["10.0.0.0/8"]
  }
  ]
  description = "Specify NLB Inbound Ports with list of maps as needed"
}

locals {
  vpc_cidr_block = data.aws_vpc.main_vpc.cidr_block
}

variable "alb_dns_name" {
  default = ""
}

variable "log_bucket_name" {
  default = ""
}