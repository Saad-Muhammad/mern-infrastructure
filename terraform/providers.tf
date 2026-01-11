#==============================================================================
# Terraform Providers Configuration
#==============================================================================
# Required providers:
# - AWS: For infrastructure provisioning
# - Kubernetes: For K8s resource management (post-cluster creation)
# - Helm: For deploying Helm charts
#==============================================================================

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }

  # Optional: S3 backend for remote state
  # Uncomment and configure for production use
  # backend "s3" {
  #   bucket         = "your-terraform-state-bucket"
  #   key            = "mern-infrastructure/terraform.tfstate"
  #   region         = "us-east-1"
  #   encrypt        = true
  #   dynamodb_table = "terraform-state-lock"
  # }
}

#------------------------------------------------------------------------------
# AWS Provider
#------------------------------------------------------------------------------
provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "Terraform"
    }
  }
}

#------------------------------------------------------------------------------
# Kubernetes Provider
# Note: This provider is configured but will only work AFTER the cluster 
# is provisioned and kubeconfig is available. For initial deployment,
# Ansible handles K8s configuration.
#------------------------------------------------------------------------------
# provider "kubernetes" {
#   host                   = "https://${module.ec2.master_private_ip}:6443"
#   cluster_ca_certificate = file("${path.module}/files/ca.crt")
#   client_certificate     = file("${path.module}/files/client.crt")
#   client_key             = file("${path.module}/files/client.key")
# }

#------------------------------------------------------------------------------
# Helm Provider
# Note: Similar to Kubernetes provider, requires cluster to be running.
# Uncomment after cluster is provisioned via Ansible.
#------------------------------------------------------------------------------
# provider "helm" {
#   kubernetes {
#     host                   = "https://${module.ec2.master_private_ip}:6443"
#     cluster_ca_certificate = file("${path.module}/files/ca.crt")
#     client_certificate     = file("${path.module}/files/client.crt")
#     client_key             = file("${path.module}/files/client.key")
#   }
# }
