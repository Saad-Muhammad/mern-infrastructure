#==============================================================================
# ALB Module - Application Load Balancer for MERN Stack
#==============================================================================
# This module creates:
# - Application Load Balancer
# - Target Groups for Frontend (30001), Backend (30002), Grafana (30003)
# - HTTP Listener with path-based routing
# - Optional HTTPS Listener
#==============================================================================

#------------------------------------------------------------------------------
# Application Load Balancer
#------------------------------------------------------------------------------
resource "aws_lb" "main" {
  name               = "${var.project_name}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [var.alb_sg_id]
  subnets            = var.public_subnet_ids

  enable_deletion_protection = false

  tags = {
    Name        = "${var.project_name}-alb"
    Environment = var.environment
  }
}

#------------------------------------------------------------------------------
# Target Group - Frontend (NodePort 30001)
#------------------------------------------------------------------------------
resource "aws_lb_target_group" "frontend" {
  name        = "${var.project_name}-tg-frontend"
  port        = 30001
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "instance"

  health_check {
    enabled             = true
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 5
    interval            = 30
    path                = "/health"
    port                = "traffic-port"
    protocol            = "HTTP"
    matcher             = "200-399"
  }

  deregistration_delay = 30

  tags = {
    Name        = "${var.project_name}-tg-frontend"
    Environment = var.environment
  }
}

#------------------------------------------------------------------------------
# Target Group - Backend (NodePort 30002)
#------------------------------------------------------------------------------
resource "aws_lb_target_group" "backend" {
  name        = "${var.project_name}-tg-backend"
  port        = 30002
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "instance"

  health_check {
    enabled             = true
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 5
    interval            = 30
    path                = "/health"
    port                = "traffic-port"
    protocol            = "HTTP"
    matcher             = "200-399"
  }

  deregistration_delay = 30

  tags = {
    Name        = "${var.project_name}-tg-backend"
    Environment = var.environment
  }
}

#------------------------------------------------------------------------------
# Target Group - Grafana (NodePort 30003)
#------------------------------------------------------------------------------
resource "aws_lb_target_group" "grafana" {
  name        = "${var.project_name}-tg-grafana"
  port        = 30003
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "instance"

  health_check {
    enabled             = true
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 5
    interval            = 30
    path                = "/api/health"
    port                = "traffic-port"
    protocol            = "HTTP"
    matcher             = "200-399"
  }

  deregistration_delay = 30

  tags = {
    Name        = "${var.project_name}-tg-grafana"
    Environment = var.environment
  }
}

#------------------------------------------------------------------------------
# Target Group Attachments - Register worker nodes
#------------------------------------------------------------------------------
resource "aws_lb_target_group_attachment" "frontend" {
  count            = length(var.worker_instance_ids)
  target_group_arn = aws_lb_target_group.frontend.arn
  target_id        = var.worker_instance_ids[count.index]
  port             = 30001
}

resource "aws_lb_target_group_attachment" "backend" {
  count            = length(var.worker_instance_ids)
  target_group_arn = aws_lb_target_group.backend.arn
  target_id        = var.worker_instance_ids[count.index]
  port             = 30002
}

resource "aws_lb_target_group_attachment" "grafana" {
  count            = length(var.worker_instance_ids)
  target_group_arn = aws_lb_target_group.grafana.arn
  target_id        = var.worker_instance_ids[count.index]
  port             = 30003
}

#------------------------------------------------------------------------------
# HTTP Listener (Port 80)
#------------------------------------------------------------------------------
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  port              = 80
  protocol          = "HTTP"

  # Default action: forward to frontend
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.frontend.arn
  }

  tags = {
    Name        = "${var.project_name}-http-listener"
    Environment = var.environment
  }
}

#------------------------------------------------------------------------------
# Listener Rules for path-based routing
#------------------------------------------------------------------------------

# Rule: /api/* → Backend
resource "aws_lb_listener_rule" "backend" {
  listener_arn = aws_lb_listener.http.arn
  priority     = 100

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.backend.arn
  }

  condition {
    path_pattern {
      values = ["/api/*"]
    }
  }

  tags = {
    Name = "${var.project_name}-rule-backend"
  }
}

# Rule: /grafana/* → Grafana
resource "aws_lb_listener_rule" "grafana" {
  listener_arn = aws_lb_listener.http.arn
  priority     = 200

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.grafana.arn
  }

  condition {
    path_pattern {
      values = ["/grafana/*", "/grafana"]
    }
  }

  tags = {
    Name = "${var.project_name}-rule-grafana"
  }
}

#------------------------------------------------------------------------------
# HTTPS Listener (Port 443) - Optional, requires ACM certificate
#------------------------------------------------------------------------------
resource "aws_lb_listener" "https" {
  count = var.acm_certificate_arn != "" ? 1 : 0

  load_balancer_arn = aws_lb.main.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = var.acm_certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.frontend.arn
  }

  tags = {
    Name        = "${var.project_name}-https-listener"
    Environment = var.environment
  }
}

# HTTPS Listener Rules (same as HTTP)
resource "aws_lb_listener_rule" "https_backend" {
  count        = var.acm_certificate_arn != "" ? 1 : 0
  listener_arn = aws_lb_listener.https[0].arn
  priority     = 100

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.backend.arn
  }

  condition {
    path_pattern {
      values = ["/api/*"]
    }
  }
}

resource "aws_lb_listener_rule" "https_grafana" {
  count        = var.acm_certificate_arn != "" ? 1 : 0
  listener_arn = aws_lb_listener.https[0].arn
  priority     = 200

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.grafana.arn
  }

  condition {
    path_pattern {
      values = ["/grafana/*", "/grafana"]
    }
  }
}
