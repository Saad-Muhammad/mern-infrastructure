#==============================================================================
# Security Groups Module Outputs
#==============================================================================

output "alb_sg_id" {
  description = "ID of the ALB security group"
  value       = aws_security_group.alb.id
}

output "bastion_sg_id" {
  description = "ID of the Bastion security group"
  value       = aws_security_group.bastion.id
}

output "k8s_master_sg_id" {
  description = "ID of the Kubernetes master security group"
  value       = aws_security_group.k8s_master.id
}

output "k8s_worker_sg_id" {
  description = "ID of the Kubernetes worker security group"
  value       = aws_security_group.k8s_worker.id
}

output "mongodb_sg_id" {
  description = "ID of the MongoDB security group"
  value       = aws_security_group.mongodb.id
}
