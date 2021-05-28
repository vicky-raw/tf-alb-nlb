data "aws_subnet_ids" "vpc_subnets" {
  vpc_id = var.vpc_id
  filter {
    name   = "tag:Name"
    values = var.subnet_names
  }
}



resource "aws_security_group" "alb_sg" {
  name   = "alb-behind-nlb-sg"
  vpc_id = var.vpc_id
  #tags   = merge(local.module_labels, map("Name", "okta-lb-sg"))

  ingress {
    protocol    = "tcp"
    self        = false
    from_port   = 80
    to_port     = 80
    cidr_blocks = ["10.0.0.0/8"]
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
  for_each                   = var.attach_ports_lb
  name                       = var.alb_name
  internal                   = true
  load_balancer_type         = "application"
  security_groups            = [aws_security_group.alb_sg.id]
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
  for_each    = var.attach_ports_lb
  name        = var.aws_lb_target_group_name
  port        = each.key
  protocol    = "HTTP"
  target_type = "instance"
  vpc_id      = var.vpc_id
  health_check {
    port                = "traffic-port"
    protocol            = "HTTP"
    healthy_threshold   = "3"
    unhealthy_threshold = "3"
  }
}

resource "aws_lb_target_group_attachment" "nonprod_tg_attachment" {
  for_each         = var.attach_ports_lb
  target_group_arn = aws_lb_target_group.alb_target_groups[each.key].arn
  target_id        = each.value
  port             = each.key
}

resource "aws_lb_listener" "dataengg-nonprod-listner" {
  for_each          = var.attach_ports_lb
  load_balancer_arn = aws_lb.alb_behind_nlb[each.key].arn
  port              = 80
  protocol          = "HTTP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.alb_target_groups[each.key].arn
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

resource "aws_lambda_function" "nlb_alb_tg_resgister" {
  filename         = "cw_alarm.zip"
  function_name    = "nlb_alb_tg_resgister"
  role             =  aws_iam_role.lambda_for_NLB_ALB.arn
  handler          = "cw_alarm.lambda_handler"
  source_code_hash = filebase64sha256("lambda_function_payload.zip")
  runtime          = "python3.8"
  timeout = 300
   environment {
    variables = {
      ALB_DNS_NAME  = "bar"
      ALB_LISTENER = 80
      S3_BUCKET = ""
      NLB_TG_ARN = ""
      MAX_LOOKUP_PER_INVOCATION = 50
      INVOCATIONS_BEFORE_DEREGISTRATION = 3
      CW_METRIC_FLAG_IP_COUNT = true
    }
}

resource "aws_cloudwatch_event_rule" "ip_change_alb" {
  name          = "capture_ip_change_alb"
  description   = "Capture IP change ALB"
  schedule_expression = "rate(1 minutes)"
}

resource "aws_cloudwatch_event_target" "ip_change_alb" {
  rule      = aws_cloudwatch_event_rule.ip_change_alb.name
  arn       = aws_lambda_function.nlb_alb_tg_resgister.arn
}
# Below not completed
/*
# NLB Resource

resource "aws_lb" "dataengg_nonprod_app_alb" {
  for_each                   = var.attach_ports_lb
  name                       = "dataengg-nonprod-app-alb-${each.key}"
  internal                   = true
  load_balancer_type         = "application"
  security_groups            = [aws_security_group.data_engg_nonprod_app_LB_sg.id]
  subnets                    = data.aws_subnet_ids.expn_vpc.ids
  enable_deletion_protection = false
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
}

resource "aws_lb_target_group" "dataengg_nonprod_app_target_group" {
  for_each    = var.attach_ports_lb
  name        = "dataengg-nonprod-app-target-${each.key}"
  port        = each.key
  protocol    = "HTTP"
  target_type = "instance"
  vpc_id      = module.expn_vpc.vpc_id
  health_check {
    port                = "traffic-port"
    protocol            = "HTTP"
    healthy_threshold   = "3"
    unhealthy_threshold = "3"
  }
}

resource "aws_lb_target_group_attachment" "nonprod_tg_attachment" {
  for_each         = var.attach_ports_lb
  target_group_arn = aws_lb_target_group.dataengg_nonprod_app_target_group[each.key].arn
  target_id        = each.value
  port             = each.key
}

resource "aws_lb_listener" "dataengg-nonprod-listner" {
  for_each          = var.attach_ports_lb
  load_balancer_arn = aws_lb.dataengg_nonprod_app_alb[each.key].arn
  port              = 80
  protocol          = "HTTP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.dataengg_nonprod_app_target_group[each.key].arn
  }
} 
*/