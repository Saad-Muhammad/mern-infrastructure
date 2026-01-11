#==============================================================================
# ALB Module Variables
#==============================================================================

variable "project_name" {
  description = "Name of the project, used for resource naming"
  type        = string
}

variable "environment" {
  description = "Environment name (e.g., production, staging)"
  type        = string
}

variable "vpc_id" {
  description = "ID of the VPC"
  type        = string
}

variable "public_subnet_ids" {
  description = "List of public subnet IDs for ALB"
  type        = list(string)
}

variable "alb_sg_id" {
  description = "Security group ID for the ALB"
  type        = string
}

variable "worker_instance_ids" {
  description = "List of worker node instance IDs for target group registration"
  type        = list(string)
}

variable "acm_certificate_arn" {
  description = "ARN of ACM certificate for HTTPS (optional, leave empty to disable HTTPS)"
  type        = string
  default     = ""
}
