#==============================================================================
# EC2 Module Outputs
#==============================================================================

#------------------------------------------------------------------------------
# Bastion Host
#------------------------------------------------------------------------------
output "bastion_public_ip" {
  description = "Public IP address of the bastion host"
  value       = aws_instance.bastion.public_ip
}

output "bastion_instance_id" {
  description = "Instance ID of the bastion host"
  value       = aws_instance.bastion.id
}

#------------------------------------------------------------------------------
# Kubernetes Master
#------------------------------------------------------------------------------
output "master_private_ip" {
  description = "Private IP address of the Kubernetes master node"
  value       = aws_instance.k8s_master.private_ip
}

output "master_instance_id" {
  description = "Instance ID of the Kubernetes master node"
  value       = aws_instance.k8s_master.id
}

#------------------------------------------------------------------------------
# Kubernetes Workers
#------------------------------------------------------------------------------
output "worker_private_ips" {
  description = "Private IP addresses of the Kubernetes worker nodes"
  value       = aws_instance.k8s_workers[*].private_ip
}

output "worker_instance_ids" {
  description = "Instance IDs of the Kubernetes worker nodes"
  value       = aws_instance.k8s_workers[*].id
}

#------------------------------------------------------------------------------
# MongoDB
#------------------------------------------------------------------------------
output "mongodb_private_ip" {
  description = "Private IP address of the MongoDB instance"
  value       = aws_instance.mongodb.private_ip
}

output "mongodb_instance_id" {
  description = "Instance ID of the MongoDB instance"
  value       = aws_instance.mongodb.id
}

#------------------------------------------------------------------------------
# AMI Info
#------------------------------------------------------------------------------
output "ami_id" {
  description = "ID of the Ubuntu AMI used"
  value       = data.aws_ami.ubuntu.id
}
