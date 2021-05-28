variable "vpc_id" {
}

variable "alb_name" {
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