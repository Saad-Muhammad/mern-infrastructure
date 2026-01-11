#==============================================================================
# Root Module Outputs
#==============================================================================
# These outputs provide essential information for post-deployment
# configuration, including IPs, DNS names, and resource IDs.
#==============================================================================

#------------------------------------------------------------------------------
# VPC Outputs
#------------------------------------------------------------------------------
output "vpc_id" {
  description = "ID of the VPC"
  value       = module.vpc.vpc_id
}

output "public_subnet_ids" {
  description = "IDs of the public subnets"
  value       = module.vpc.public_subnet_ids
}

output "private_subnet_ids" {
  description = "IDs of the private subnets"
  value       = module.vpc.private_subnet_ids
}

output "nat_gateway_ip" {
  description = "Public IP of the NAT Gateway"
  value       = module.vpc.nat_gateway_public_ip
}

#------------------------------------------------------------------------------
# Security Group Outputs
#------------------------------------------------------------------------------
output "alb_security_group_id" {
  description = "ID of the ALB security group"
  value       = module.security_groups.alb_sg_id
}

output "bastion_security_group_id" {
  description = "ID of the bastion security group"
  value       = module.security_groups.bastion_sg_id
}

output "k8s_master_security_group_id" {
  description = "ID of the Kubernetes master security group"
  value       = module.security_groups.k8s_master_sg_id
}

output "k8s_worker_security_group_id" {
  description = "ID of the Kubernetes worker security group"
  value       = module.security_groups.k8s_worker_sg_id
}

output "mongodb_security_group_id" {
  description = "ID of the MongoDB security group"
  value       = module.security_groups.mongodb_sg_id
}

#------------------------------------------------------------------------------
# EC2 Instance Outputs
#------------------------------------------------------------------------------
output "bastion_public_ip" {
  description = "Public IP of the bastion host"
  value       = module.ec2.bastion_public_ip
}

output "master_private_ip" {
  description = "Private IP of the Kubernetes master node"
  value       = module.ec2.master_private_ip
}

output "worker_private_ips" {
  description = "Private IPs of the Kubernetes worker nodes"
  value       = module.ec2.worker_private_ips
}

output "mongodb_private_ip" {
  description = "Private IP of the MongoDB instance"
  value       = module.ec2.mongodb_private_ip
}

#------------------------------------------------------------------------------
# ALB Outputs
#------------------------------------------------------------------------------
output "alb_dns_name" {
  description = "DNS name of the Application Load Balancer"
  value       = module.alb.alb_dns_name
}

output "alb_arn" {
  description = "ARN of the Application Load Balancer"
  value       = module.alb.alb_arn
}

#------------------------------------------------------------------------------
# Access Information
#------------------------------------------------------------------------------
output "ssh_bastion_command" {
  description = "SSH command to connect to bastion host"
  value       = "ssh -i <your-key.pem> ubuntu@${module.ec2.bastion_public_ip}"
}

output "ssh_master_command" {
  description = "SSH command to connect to K8s master via bastion"
  value       = "ssh -i <your-key.pem> -J ubuntu@${module.ec2.bastion_public_ip} ubuntu@${module.ec2.master_private_ip}"
}

output "app_url" {
  description = "URL to access the application"
  value       = "http://${module.alb.alb_dns_name}"
}

output "grafana_url" {
  description = "URL to access Grafana"
  value       = "http://${module.alb.alb_dns_name}/grafana"
}

output "api_url" {
  description = "URL to access the backend API"
  value       = "http://${module.alb.alb_dns_name}/api"
}

#------------------------------------------------------------------------------
# Ansible Inventory Helper - Use this to generate inventory
#------------------------------------------------------------------------------
output "ansible_inventory" {
  description = "Helper data for generating Ansible inventory"
  value = {
    bastion_ip  = module.ec2.bastion_public_ip
    master_ip   = module.ec2.master_private_ip
    worker_ips  = module.ec2.worker_private_ips
    mongodb_ip  = module.ec2.mongodb_private_ip
  }
}
