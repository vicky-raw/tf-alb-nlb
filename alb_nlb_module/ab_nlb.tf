data "aws_subnet_ids" "vpc_subnets" {
  vpc_id = var.vpc_id
  filter {
    name   = "tag:Name"
    values = var.subnet_names
  }
}

data "aws_vpc" "main_vpc" {
  id = var.vpc_id
}


resource "aws_security_group" "nlb_sg" {
  name   = "nlb-before-alb-sg"
  vpc_id = var.vpc_id
  #tags   = merge(local.module_labels, map("Name", ""))
  dynamic "ingress" {
   for_each = [
     for i in var.nlb_inbound_ports :
       {
           from_port       = i.from_port
           to_port         = i.to_port
           cidr_blocks     = try(i.cidr_block, [data.aws_vpc.main_vpc.cidr_block])
       } 
   ]
   content {
     from_port       = ingress.value.from_port
     to_port         = ingress.value.to_port
     protocol        =    "tcp"
     self        = false
     cidr_blocks = ingress.value.cidr_blocks
   }
 }

  egress {
    protocol    = "-1"
    from_port   = 0
    to_port     = 0
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# ALB Resource

resource "aws_lb" "alb_behind_nlb" {
  name                       = var.nlb_name
  internal                   = true
  load_balancer_type         = "network"
  security_groups            = [aws_security_group.nlb_sg.id]
  subnets                    = data.aws_subnet_ids.vpc_subnets.ids
  enable_deletion_protection = false
  /*
  access_logs {
    bucket  = "${local.account_id}-logs-${var.region}"
    prefix  = "lb_accesslog"
    enabled = true
  }

  tags = {
    Environment = "nonprod"
    Name        = "dataengg-nonprod-lb-${each.key}"
    Description = "Data Engineering nonprod Internal application LB"
  }
  */
}

resource "aws_lb_target_group" "alb_target_groups" {
  name        = var.aws_lb_target_group_name
  port        = 80
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = var.vpc_id
  health_check {
    port                = "traffic-port"
    protocol            = "HTTP"
    healthy_threshold   = "3"
    unhealthy_threshold = "3"
  }
}

/*
resource "aws_lb_target_group_attachment" "nonprod_tg_attachment" {
  for_each         = var.attach_ports_lb
  target_group_arn = aws_lb_target_group.alb_target_groups[each.key].arn
  target_id        = each.value
  port             = each.key
}
*/

resource "aws_lb_listener" "nlb_listener" {
  load_balancer_arn = aws_lb.alb_behind_nlb.arn
  port              = 80
  protocol          = "HTTP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.alb_target_groups.arn
  }
}

resource "aws_iam_role" "lambda_for_NLB_ALB" {
  name               = var.lambda_role_name
  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "lambda.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
}

resource "aws_iam_policy" "lambda_for_NLB_ALB_policy" {
  name   = "${var.lambda_role_name}-policy"
  policy = file("${path.module}/templates/lambda_for_NLB_ALB_policy.json")
}

resource "aws_iam_role_policy_attachment" "ascend_data_engg_nonprod_lambda_role_attach_1" {
  role       = aws_iam_role.lambda_for_NLB_ALB.name
  policy_arn = aws_iam_policy.lambda_for_NLB_ALB_policy.arn
}

resource "aws_lambda_function" "nlb_alb_tg_register" {
  filename         = "${path.module}/populate_NLB_TG_with_ALB.zip"
  function_name    = "nlb_alb_tg_register"
  role             =  aws_iam_role.lambda_for_NLB_ALB.arn
  handler          = "populate_NLB_TG_with_ALB.lambda_handler"
  source_code_hash = filebase64sha256("${path.module}/populate_NLB_TG_with_ALB.zip")
  runtime          = "python3.8"
  timeout = 300
   environment {
    variables = {
      ALB_DNS_NAME  = var.alb_dns_name
      ALB_LISTENER = 80
      S3_BUCKET = aws_s3_bucket.NLB_to_ALB_bucket.id
      NLB_TG_ARN = aws_lb_target_group.alb_target_groups.arn
      MAX_LOOKUP_PER_INVOCATION = 50
      INVOCATIONS_BEFORE_DEREGISTRATION = 3
      CW_METRIC_FLAG_IP_COUNT = true
    }
}
}

resource "aws_cloudwatch_event_rule" "ip_change_alb" {
  name          = "capture_ip_change_alb"
  description   = "Capture IP change ALB"
  schedule_expression = "rate(1 minutes)"
}

resource "aws_cloudwatch_event_target" "ip_change_alb" {
  rule      = aws_cloudwatch_event_rule.ip_change_alb.name
  arn       = aws_lambda_function.nlb_alb_tg_register.arn
}

resource "aws_s3_bucket" "NLB_to_ALB_bucket" {
  bucket = "NLB-to-ALB-register-bucket"
  acl    = "private"
  #tags = merge(local.module_tags, map("Name", "NLB-to-ALB-register-bucket"))
  server_side_encryption_configuration {
    rule {
      apply_server_side_encryption_by_default {
        sse_algorithm = "AES256"
      }
    }
  }
  versioning {
    enabled = true
  }
  logging {
    target_bucket = var.log_bucket_name
    target_prefix = "configs/"
  }
  lifecycle {
    prevent_destroy = false
  }
  policy = <<POLICY
{
    "Version": "2012-10-17",
    "Id": "S3BucketPolicyexpn-NLB-to-ALB-register-bucket",
    "Statement": [
        {
            "Sid": "DenyIncorrectEncryptionHeader",
            "Effect": "Deny",
            "Principal": "*",
            "Action": "s3:PutObject",
            "Resource": "arn:aws:s3:::NLB-to-ALB-register-bucket/*",
            "Condition": {
                "StringNotEquals": {
                    "s3:x-amz-server-side-encryption": "AES256"
                }
            }
        },
        {
            "Sid": "DenyUnEncryptedObjectUploads",
            "Effect": "Deny",
            "Principal": "*",
            "Action": "s3:PutObject",
            "Resource": "arn:aws:s3:::NLB-to-ALB-register-bucket/*",
            "Condition": {
                "Null": {
                    "s3:x-amz-server-side-encryption": "true"
                }
            }
        },
        {
            "Sid": "DenyNonSSLAccess",
            "Effect": "Deny",
            "Principal": "*",
            "Action": "s3:*",
            "Resource": "arn:aws:s3:::NLB-to-ALB-register-bucket/*",
            "Condition": {
                "Bool": {
                    "aws:SecureTransport": "false"
                }
            }
        }
    ]
}
POLICY
}