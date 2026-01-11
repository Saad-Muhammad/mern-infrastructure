#==============================================================================
# Root Module - MERN Stack Infrastructure on AWS
#==============================================================================
# This is the main Terraform configuration that orchestrates all modules
# to create the complete infrastructure for a MERN stack application.
#
# Infrastructure Components:
# - VPC with public/private subnets
# - Security groups for all components
# - EC2 instances (K8s master, workers, MongoDB, bastion)
# - Application Load Balancer with path-based routing
#==============================================================================

#------------------------------------------------------------------------------
# VPC Module - Network Infrastructure
#------------------------------------------------------------------------------
module "vpc" {
  source = "./modules/vpc"

  project_name         = var.project_name
  environment          = var.environment
  vpc_cidr             = var.vpc_cidr
  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs
}

#------------------------------------------------------------------------------
# Security Groups Module - Network Security
#------------------------------------------------------------------------------
module "security_groups" {
  source = "./modules/security-groups"

  project_name         = var.project_name
  environment          = var.environment
  vpc_id               = module.vpc.vpc_id
  private_subnet_cidrs = var.private_subnet_cidrs
  allowed_ssh_cidrs    = var.allowed_ssh_cidrs
}

#------------------------------------------------------------------------------
# EC2 Module - Compute Instances
#------------------------------------------------------------------------------
module "ec2" {
  source = "./modules/ec2"

  project_name          = var.project_name
  environment           = var.environment
  key_name              = var.key_name
  public_subnet_ids     = module.vpc.public_subnet_ids
  private_subnet_ids    = module.vpc.private_subnet_ids
  bastion_sg_id         = module.security_groups.bastion_sg_id
  k8s_master_sg_id      = module.security_groups.k8s_master_sg_id
  k8s_worker_sg_id      = module.security_groups.k8s_worker_sg_id
  mongodb_sg_id         = module.security_groups.mongodb_sg_id
  bastion_instance_type = var.bastion_instance_type
  master_instance_type  = var.master_instance_type
  worker_instance_type  = var.worker_instance_type
  mongodb_instance_type = var.mongodb_instance_type
  worker_count          = var.worker_count
  mongodb_ebs_size      = var.mongodb_ebs_size
}

#------------------------------------------------------------------------------
# ALB Module - Load Balancer
#------------------------------------------------------------------------------
module "alb" {
  source = "./modules/alb"

  project_name        = var.project_name
  environment         = var.environment
  vpc_id              = module.vpc.vpc_id
  public_subnet_ids   = module.vpc.public_subnet_ids
  alb_sg_id           = module.security_groups.alb_sg_id
  worker_instance_ids = module.ec2.worker_instance_ids
  acm_certificate_arn = var.acm_certificate_arn
}
