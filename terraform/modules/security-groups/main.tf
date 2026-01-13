#==============================================================================
# Security Groups Module - Network security for all components
#==============================================================================
# Creates security groups for:
# - Application Load Balancer
# - Kubernetes Master Node
# - Kubernetes Worker Nodes
# - MongoDB Instance
# - Bastion Host
#==============================================================================

#------------------------------------------------------------------------------
# ALB Security Group
# Allows HTTP/HTTPS from internet, egress to worker NodePorts
#------------------------------------------------------------------------------
resource "aws_security_group" "alb" {
  name        = "${var.project_name}-alb-sg"
  description = "Security group for Application Load Balancer"
  vpc_id      = var.vpc_id

  # HTTP from anywhere
  ingress {
    description = "HTTP from internet"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # HTTPS from anywhere
  ingress {
    description = "HTTPS from internet"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Egress to worker NodePort range
  egress {
    description = "To worker NodePorts"
    from_port   = 30000
    to_port     = 32767
    protocol    = "tcp"
    cidr_blocks = var.private_subnet_cidrs
  }

  tags = {
    Name        = "${var.project_name}-alb-sg"
    Environment = var.environment
  }
}

#------------------------------------------------------------------------------
# Bastion Security Group
# SSH access from allowed IPs only
#------------------------------------------------------------------------------
resource "aws_security_group" "bastion" {
  name        = "${var.project_name}-bastion-sg"
  description = "Security group for Bastion Host"
  vpc_id      = var.vpc_id

  # SSH from allowed IPs
  ingress {
    description = "SSH from allowed IPs"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.allowed_ssh_cidrs
  }

  # Allow all outbound
  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "${var.project_name}-bastion-sg"
    Environment = var.environment
  }
}

#------------------------------------------------------------------------------
# Kubernetes Master Security Group
# Control plane access from workers and bastion
#------------------------------------------------------------------------------
resource "aws_security_group" "k8s_master" {
  name        = "${var.project_name}-k8s-master-sg"
  description = "Security group for Kubernetes Master Node"
  vpc_id      = var.vpc_id

  # SSH from bastion
  ingress {
    description     = "SSH from bastion"
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.bastion.id]
  }

  # Kubernetes API server
  ingress {
    description = "Kubernetes API server"
    from_port   = 6443
    to_port     = 6443
    protocol    = "tcp"
    cidr_blocks = var.private_subnet_cidrs
  }

  # etcd server client API
  ingress {
    description = "etcd server client API"
    from_port   = 2379
    to_port     = 2380
    protocol    = "tcp"
    cidr_blocks = var.private_subnet_cidrs
  }

  # Kubelet API
  ingress {
    description = "Kubelet API"
    from_port   = 10250
    to_port     = 10250
    protocol    = "tcp"
    cidr_blocks = var.private_subnet_cidrs
  }

  # kube-scheduler
  ingress {
    description = "kube-scheduler"
    from_port   = 10251
    to_port     = 10251
    protocol    = "tcp"
    cidr_blocks = var.private_subnet_cidrs
  }

  # kube-controller-manager
  ingress {
    description = "kube-controller-manager"
    from_port   = 10252
    to_port     = 10252
    protocol    = "tcp"
    cidr_blocks = var.private_subnet_cidrs
  }

  # Allow all outbound
  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "${var.project_name}-k8s-master-sg"
    Environment = var.environment
    Role        = "master"
  }
}

#------------------------------------------------------------------------------
# Kubernetes Worker Security Group
# NodePort access from ALB, pod-to-pod communication
#------------------------------------------------------------------------------
resource "aws_security_group" "k8s_worker" {
  name        = "${var.project_name}-k8s-worker-sg"
  description = "Security group for Kubernetes Worker Nodes"
  vpc_id      = var.vpc_id

  # SSH from bastion
  ingress {
    description     = "SSH from bastion"
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.bastion.id]
  }

  # NodePort Services from Bastion (for SSH Tunneling)
  ingress {
    description     = "ArgoCD NodePort from bastion"
    from_port       = 30080
    to_port         = 30080
    protocol        = "tcp"
    security_groups = [aws_security_group.bastion.id]
  }

  # NodePort Services from ALB
  ingress {
    description     = "NodePort services from ALB"
    from_port       = 30000
    to_port         = 32767
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  # Kubelet API from master
  ingress {
    description     = "Kubelet API from master"
    from_port       = 10250
    to_port         = 10250
    protocol        = "tcp"
    security_groups = [aws_security_group.k8s_master.id]
  }

  # Allow all outbound
  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "${var.project_name}-k8s-worker-sg"
    Environment = var.environment
    Role        = "worker"
  }
}

# Worker-to-worker communication (pod network)
resource "aws_security_group_rule" "worker_self" {
  type                     = "ingress"
  from_port                = 0
  to_port                  = 65535
  protocol                 = "-1"
  security_group_id        = aws_security_group.k8s_worker.id
  source_security_group_id = aws_security_group.k8s_worker.id
  description              = "All traffic from self (pod network)"
}

# Worker-to-master communication
resource "aws_security_group_rule" "worker_to_master" {
  type                     = "ingress"
  from_port                = 0
  to_port                  = 65535
  protocol                 = "-1"
  security_group_id        = aws_security_group.k8s_master.id
  source_security_group_id = aws_security_group.k8s_worker.id
  description              = "All traffic from workers"
}

# Master-to-worker communication
resource "aws_security_group_rule" "master_to_worker" {
  type                     = "ingress"
  from_port                = 0
  to_port                  = 65535
  protocol                 = "-1"
  security_group_id        = aws_security_group.k8s_worker.id
  source_security_group_id = aws_security_group.k8s_master.id
  description              = "All traffic from master"
}

#------------------------------------------------------------------------------
# MongoDB Security Group
# Access from K8s workers only
#------------------------------------------------------------------------------
resource "aws_security_group" "mongodb" {
  name        = "${var.project_name}-mongodb-sg"
  description = "Security group for MongoDB Instance"
  vpc_id      = var.vpc_id

  # SSH from bastion
  ingress {
    description     = "SSH from bastion"
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.bastion.id]
  }

  # MongoDB from workers
  ingress {
    description     = "MongoDB from K8s workers"
    from_port       = 27017
    to_port         = 27017
    protocol        = "tcp"
    security_groups = [aws_security_group.k8s_worker.id]
  }

  # MongoDB Exporter from workers (for Prometheus scraping)
  ingress {
    description     = "MongoDB Exporter from K8s workers"
    from_port       = 9216
    to_port         = 9216
    protocol        = "tcp"
    security_groups = [aws_security_group.k8s_worker.id]
  }

  # Allow all outbound
  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "${var.project_name}-mongodb-sg"
    Environment = var.environment
    Role        = "database"
  }
}
