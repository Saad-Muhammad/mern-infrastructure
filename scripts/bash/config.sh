#!/bin/bash
#==============================================================================
# Configuration Variables for MERN Infrastructure
#==============================================================================
# This file contains all configuration variables used by the bash scripts.
# Mirrors the Ansible group_vars/all.yml configuration.
#==============================================================================

#------------------------------------------------------------------------------
# SSH Configuration
#------------------------------------------------------------------------------
# Update this path to your actual SSH key location
SSH_KEY_PATH="/c/Users/User/Documents/AWS/aws-rsa-keys.pem"
SSH_USER="ubuntu"

#------------------------------------------------------------------------------
# Host Configuration (will be populated from Terraform outputs)
#------------------------------------------------------------------------------
BASTION_IP="51.20.69.193"
MASTER_IP="10.0.10.108"
WORKER_IPS="10.0.10.58 10.0.11.164"  # Space-separated list
MONGODB_IP="10.0.11.30"

#------------------------------------------------------------------------------
# Kubernetes Configuration
#------------------------------------------------------------------------------
KUBERNETES_VERSION="1.29"
POD_NETWORK_CIDR="10.244.0.0/16"
SERVICE_CIDR="10.96.0.0/12"

# Container runtime
CONTAINER_RUNTIME="containerd"
CONTAINERD_VERSION="${CONTAINERD_VERSION:-1.7.*}"

# Calico CNI
CALICO_VERSION="${CALICO_VERSION:-v3.27.0}"

#------------------------------------------------------------------------------
# MongoDB Configuration
#------------------------------------------------------------------------------
MONGODB_VERSION="${MONGODB_VERSION:-7.0}"
MONGODB_PORT="${MONGODB_PORT:-27017}"
MONGODB_DATA_DIR="${MONGODB_DATA_DIR:-/data/mongodb}"
MONGODB_LOG_DIR="${MONGODB_LOG_DIR:-/var/log/mongodb}"

# MongoDB credentials
MONGODB_ADMIN_USER="${MONGODB_ADMIN_USER:-admin}"
MONGODB_ADMIN_PASSWORD="${MONGODB_ADMIN_PASSWORD:-admin}"
MONGODB_APP_DATABASE="${MONGODB_APP_DATABASE:-todo_app}"
MONGODB_APP_USER="${MONGODB_APP_USER:-todo_user}"
MONGODB_APP_PASSWORD="${MONGODB_APP_PASSWORD:-admin}"

# MongoDB Exporter
MONGODB_EXPORTER_VERSION="${MONGODB_EXPORTER_VERSION:-0.40.0}"
MONGODB_EXPORTER_USER="${MONGODB_EXPORTER_USER:-exporter}"
MONGODB_EXPORTER_PASSWORD="${MONGODB_EXPORTER_PASSWORD:-exporter_password}"

#------------------------------------------------------------------------------
# Monitoring Configuration
#------------------------------------------------------------------------------
GRAFANA_ADMIN_PASSWORD="${GRAFANA_ADMIN_PASSWORD:-admin}"
PROMETHEUS_RETENTION="${PROMETHEUS_RETENTION:-15d}"
PROMETHEUS_STORAGE_SIZE="${PROMETHEUS_STORAGE_SIZE:-50Gi}"

# Node ports for services
GRAFANA_NODEPORT="${GRAFANA_NODEPORT:-30003}"
ARGOCD_NODEPORT="${ARGOCD_NODEPORT:-30080}"

#------------------------------------------------------------------------------
# Application Configuration
#------------------------------------------------------------------------------
APP_NAMESPACE="${APP_NAMESPACE:-mern-app}"
DOCKER_REGISTRY="${DOCKER_REGISTRY:-docker.io}"
DOCKER_USERNAME="${DOCKER_USERNAME:-mrtoast07}"

#------------------------------------------------------------------------------
# ArgoCD Configuration
#------------------------------------------------------------------------------
ARGOCD_NAMESPACE="${ARGOCD_NAMESPACE:-argocd}"
ARGOCD_VERSION="${ARGOCD_VERSION:-stable}"
GITHUB_REPO_URL="${GITHUB_REPO_URL:-https://github.com/Saad-Muhammad/mern-infrastructure/}"
GITHUB_REPO_BRANCH="${GITHUB_REPO_BRANCH:-main}"

#------------------------------------------------------------------------------
# Helm Repositories
#------------------------------------------------------------------------------
HELM_REPOS=(
    "prometheus-community|https://prometheus-community.github.io/helm-charts"
    "grafana|https://grafana.github.io/helm-charts"
    "argo|https://argoproj.github.io/argo-helm"
)
