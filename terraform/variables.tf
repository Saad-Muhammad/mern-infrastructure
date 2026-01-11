#==============================================================================
# Root Module Variables
#==============================================================================
# These variables are used across all modules and can be customized via
# terraform.tfvars or command-line arguments.
#==============================================================================

#------------------------------------------------------------------------------
# General Settings
#------------------------------------------------------------------------------
variable "project_name" {
  description = "Name of the project, used for resource naming and tagging"
  type        = string
  default     = "mern-app"

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "environment" {
  description = "Environment name (e.g., production, staging, development)"
  type        = string
  default     = "production"

  validation {
    condition     = contains(["production", "staging", "development"], var.environment)
    error_message = "Environment must be one of: production, staging, development."
  }
}

variable "aws_region" {
  description = "AWS region for resource deployment"
  type        = string
  default     = "us-east-1"
}

#------------------------------------------------------------------------------
# Network Configuration
#------------------------------------------------------------------------------
variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "List of CIDR blocks for public subnets"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnet_cidrs" {
  description = "List of CIDR blocks for private subnets"
  type        = list(string)
  default     = ["10.0.10.0/24", "10.0.11.0/24"]
}

#------------------------------------------------------------------------------
# Security Configuration
#------------------------------------------------------------------------------
variable "allowed_ssh_cidrs" {
  description = "List of CIDR blocks allowed to SSH to bastion host"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "key_name" {
  description = "Name of the AWS key pair for SSH access"
  type        = string
}

#------------------------------------------------------------------------------
# EC2 Instance Configuration
#------------------------------------------------------------------------------
variable "bastion_instance_type" {
  description = "Instance type for bastion host"
  type        = string
  default     = "t3.micro"
}

variable "master_instance_type" {
  description = "Instance type for Kubernetes master node"
  type        = string
  default     = "t3.medium"
}

variable "worker_instance_type" {
  description = "Instance type for Kubernetes worker nodes"
  type        = string
  default     = "t3.medium"
}

variable "mongodb_instance_type" {
  description = "Instance type for MongoDB server"
  type        = string
  default     = "t3.large"
}

variable "worker_count" {
  description = "Number of Kubernetes worker nodes"
  type        = number
  default     = 2
}

variable "mongodb_ebs_size" {
  description = "Size of MongoDB data EBS volume in GB"
  type        = number
  default     = 100
}

#------------------------------------------------------------------------------
# SSL/TLS Configuration
#------------------------------------------------------------------------------
variable "acm_certificate_arn" {
  description = "ARN of ACM certificate for HTTPS (leave empty to disable HTTPS)"
  type        = string
  default     = ""
}
