#==============================================================================
# EC2 Module Variables
#==============================================================================

variable "project_name" {
  description = "Name of the project, used for resource naming"
  type        = string
}

variable "environment" {
  description = "Environment name (e.g., production, staging)"
  type        = string
}

variable "key_name" {
  description = "Name of the SSH key pair for EC2 instances"
  type        = string
}

#------------------------------------------------------------------------------
# Subnet Configuration
#------------------------------------------------------------------------------
variable "public_subnet_ids" {
  description = "List of public subnet IDs"
  type        = list(string)
}

variable "private_subnet_ids" {
  description = "List of private subnet IDs"
  type        = list(string)
}

#------------------------------------------------------------------------------
# Security Group IDs
#------------------------------------------------------------------------------
variable "bastion_sg_id" {
  description = "Security group ID for bastion host"
  type        = string
}

variable "k8s_master_sg_id" {
  description = "Security group ID for Kubernetes master"
  type        = string
}

variable "k8s_worker_sg_id" {
  description = "Security group ID for Kubernetes workers"
  type        = string
}

variable "mongodb_sg_id" {
  description = "Security group ID for MongoDB"
  type        = string
}

#------------------------------------------------------------------------------
# Instance Types
#------------------------------------------------------------------------------
variable "bastion_instance_type" {
  description = "Instance type for bastion host"
  type        = string
  default     = "t3.micro"
}

variable "master_instance_type" {
  description = "Instance type for Kubernetes master"
  type        = string
  default     = "t3.medium"
}

variable "worker_instance_type" {
  description = "Instance type for Kubernetes workers"
  type        = string
  default     = "t3.medium"
}

variable "mongodb_instance_type" {
  description = "Instance type for MongoDB"
  type        = string
  default     = "t3.large"
}

#------------------------------------------------------------------------------
# Cluster Configuration
#------------------------------------------------------------------------------
variable "worker_count" {
  description = "Number of Kubernetes worker nodes"
  type        = number
  default     = 2

  validation {
    condition     = var.worker_count >= 1 && var.worker_count <= 10
    error_message = "Worker count must be between 1 and 10."
  }
}

variable "mongodb_ebs_size" {
  description = "Size of the MongoDB data EBS volume in GB"
  type        = number
  default     = 100

  validation {
    condition     = var.mongodb_ebs_size >= 20
    error_message = "MongoDB EBS volume must be at least 20 GB."
  }
}
