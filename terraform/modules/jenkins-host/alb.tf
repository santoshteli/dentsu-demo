################################################################################
# Optional internet-facing ALB in front of Jenkins, for browser-only access
# when the SSM port-forward is not available (for example, a demo machine
# without the AWS CLI). The host itself stays in the private subnet with no
# public IP; only this ALB may reach it on 8080.
#
# No inbound rule is created by default. Add one for the current client IP
# when needed (console: Edit inbound rules > HTTP > Source: My IP), or pass
# CIDRs in var.alb_allowed_cidrs. Rules added in the console are not managed
# by Terraform, so they never conflict with it; remove them afterwards.
################################################################################

locals {
  alb_name = "${var.name_prefix}-jenkins-alb"
}

resource "aws_security_group" "alb" {
  count = var.enable_public_alb ? 1 : 0

  name        = local.alb_name
  description = "Jenkins ALB: HTTP from allowed client IPs only, to Jenkins on 8080"
  vpc_id      = var.vpc_id

  tags = merge(var.tags, { Name = local.alb_name })
}

resource "aws_vpc_security_group_ingress_rule" "alb_http" {
  for_each = var.enable_public_alb ? toset(var.alb_allowed_cidrs) : toset([])

  security_group_id = aws_security_group.alb[0].id
  description       = "HTTP from ${each.value}"
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
  cidr_ipv4         = each.value

  tags = merge(var.tags, { Name = "${local.alb_name}-http-${each.value}" })
}

resource "aws_vpc_security_group_egress_rule" "alb_to_jenkins" {
  count = var.enable_public_alb ? 1 : 0

  security_group_id            = aws_security_group.alb[0].id
  description                  = "To Jenkins on 8080"
  ip_protocol                  = "tcp"
  from_port                    = 8080
  to_port                      = 8080
  referenced_security_group_id = aws_security_group.this.id

  tags = merge(var.tags, { Name = "${local.alb_name}-to-jenkins" })
}

resource "aws_vpc_security_group_ingress_rule" "jenkins_from_alb" {
  count = var.enable_public_alb ? 1 : 0

  security_group_id            = aws_security_group.this.id
  description                  = "Jenkins UI from the Jenkins ALB only"
  ip_protocol                  = "tcp"
  from_port                    = 8080
  to_port                      = 8080
  referenced_security_group_id = aws_security_group.alb[0].id

  tags = merge(var.tags, { Name = "${local.name}-from-alb" })
}

resource "aws_lb" "jenkins" {
  count = var.enable_public_alb ? 1 : 0

  name               = local.alb_name
  load_balancer_type = "application"
  internal           = false
  subnets            = var.public_subnet_ids
  security_groups    = [aws_security_group.alb[0].id]

  drop_invalid_header_fields = true

  tags = merge(var.tags, { Name = local.alb_name })

  lifecycle {
    precondition {
      condition     = length(var.public_subnet_ids) >= 2
      error_message = "The Jenkins ALB needs public subnets in at least two AZs."
    }
  }
}

resource "aws_lb_target_group" "jenkins" {
  count = var.enable_public_alb ? 1 : 0

  name        = "${var.name_prefix}-jenkins"
  port        = 8080
  protocol    = "HTTP"
  target_type = "instance"
  vpc_id      = var.vpc_id

  deregistration_delay = 30

  # /login answers 200 without authentication, before and after the setup wizard.
  health_check {
    path                = "/login"
    matcher             = "200-399"
    interval            = 30
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }

  tags = merge(var.tags, { Name = "${var.name_prefix}-jenkins" })
}

resource "aws_lb_target_group_attachment" "jenkins" {
  count = var.enable_public_alb ? 1 : 0

  target_group_arn = aws_lb_target_group.jenkins[0].arn
  target_id        = aws_instance.this.id
  port             = 8080
}

# Plain HTTP: there is no domain, so no ACM certificate. Access is limited by
# source IP, and the ALB is switched off when not needed.
resource "aws_lb_listener" "http" {
  count = var.enable_public_alb ? 1 : 0

  load_balancer_arn = aws_lb.jenkins[0].arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.jenkins[0].arn
  }

  tags = merge(var.tags, { Name = "${local.alb_name}-http" })
}
