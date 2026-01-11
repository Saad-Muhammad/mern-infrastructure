#==============================================================================
# EC2 Module - Creates all EC2 instances for the infrastructure
#==============================================================================
# This module creates:
# - Kubernetes Master Node (1x t3.medium)
# - Kubernetes Worker Nodes (2x t3.medium)
# - MongoDB Instance (1x t3.large with additional EBS)
# - Bastion Host (1x t3.micro)
#==============================================================================

# Get latest Ubuntu 22.04 AMI
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

#------------------------------------------------------------------------------
# Bastion Host - Jump server for SSH access to private instances
#------------------------------------------------------------------------------
resource "aws_instance" "bastion" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.bastion_instance_type
  key_name                    = var.key_name
  subnet_id                   = var.public_subnet_ids[0]
  vpc_security_group_ids      = [var.bastion_sg_id]
  associate_public_ip_address = true

  root_block_device {
    volume_size           = 20
    volume_type           = "gp3"
    encrypted             = true
    delete_on_termination = true
  }

  user_data = <<-EOF
              #!/bin/bash
              hostnamectl set-hostname bastion-host
              echo "127.0.0.1 bastion-host" >> /etc/hosts
              EOF

  tags = {
    Name        = "${var.project_name}-bastion"
    Environment = var.environment
    Role        = "bastion"
  }
}

#------------------------------------------------------------------------------
# Kubernetes Master Node
#------------------------------------------------------------------------------
resource "aws_instance" "k8s_master" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.master_instance_type
  key_name               = var.key_name
  subnet_id              = var.private_subnet_ids[0]
  vpc_security_group_ids = [var.k8s_master_sg_id]

  root_block_device {
    volume_size           = 30
    volume_type           = "gp3"
    encrypted             = true
    delete_on_termination = true
  }

  user_data = <<-EOF
              #!/bin/bash
              hostnamectl set-hostname k8s-master
              echo "127.0.0.1 k8s-master" >> /etc/hosts
              EOF

  tags = {
    Name        = "${var.project_name}-k8s-master"
    Environment = var.environment
    Role        = "master"
    Kubernetes  = "true"
  }
}

#------------------------------------------------------------------------------
# Kubernetes Worker Nodes
#------------------------------------------------------------------------------
resource "aws_instance" "k8s_workers" {
  count = var.worker_count

  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.worker_instance_type
  key_name               = var.key_name
  subnet_id              = var.private_subnet_ids[count.index % length(var.private_subnet_ids)]
  vpc_security_group_ids = [var.k8s_worker_sg_id]

  root_block_device {
    volume_size           = 30
    volume_type           = "gp3"
    encrypted             = true
    delete_on_termination = true
  }

  user_data = <<-EOF
              #!/bin/bash
              hostnamectl set-hostname k8s-worker-${count.index + 1}
              echo "127.0.0.1 k8s-worker-${count.index + 1}" >> /etc/hosts
              EOF

  tags = {
    Name        = "${var.project_name}-k8s-worker-${count.index + 1}"
    Environment = var.environment
    Role        = "worker"
    Kubernetes  = "true"
  }
}

#------------------------------------------------------------------------------
# MongoDB Instance with dedicated EBS volume
#------------------------------------------------------------------------------
resource "aws_instance" "mongodb" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.mongodb_instance_type
  key_name               = var.key_name
  subnet_id              = var.private_subnet_ids[1]
  vpc_security_group_ids = [var.mongodb_sg_id]

  root_block_device {
    volume_size           = 30
    volume_type           = "gp3"
    encrypted             = true
    delete_on_termination = true
  }

  user_data = <<-EOF
              #!/bin/bash
              hostnamectl set-hostname mongodb-server
              echo "127.0.0.1 mongodb-server" >> /etc/hosts
              EOF

  tags = {
    Name        = "${var.project_name}-mongodb"
    Environment = var.environment
    Role        = "database"
  }
}

# Additional EBS volume for MongoDB data
resource "aws_ebs_volume" "mongodb_data" {
  availability_zone = aws_instance.mongodb.availability_zone
  size              = var.mongodb_ebs_size
  type              = "gp3"
  encrypted         = true

  tags = {
    Name        = "${var.project_name}-mongodb-data"
    Environment = var.environment
  }
}

# Attach EBS volume to MongoDB instance
resource "aws_volume_attachment" "mongodb_data" {
  device_name = "/dev/sdf"
  volume_id   = aws_ebs_volume.mongodb_data.id
  instance_id = aws_instance.mongodb.id
}
