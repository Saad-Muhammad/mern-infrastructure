#!/bin/bash
#==============================================================================
# MERN Infrastructure Setup Script
#==============================================================================
# This script automates the complete infrastructure setup process:
# 1. Validates prerequisites
# 2. Runs Terraform to provision AWS infrastructure
# 3. Generates Ansible inventory from Terraform outputs
# 4. Runs Ansible playbooks to configure the cluster
# 5. Displays access information
#
# Usage: ./scripts/setup.sh [options]
# Options:
#   --terraform-only    Only run Terraform
#   --ansible-only      Only run Ansible (requires existing inventory)
#   --skip-apply        Skip Terraform apply (plan only)
#   --help              Show this help message
#==============================================================================

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
TERRAFORM_DIR="$PROJECT_ROOT/terraform"
ANSIBLE_DIR="$PROJECT_ROOT/ansible"

# Default options
TERRAFORM_ONLY=false
ANSIBLE_ONLY=false
SKIP_APPLY=false

#------------------------------------------------------------------------------
# Helper Functions
#------------------------------------------------------------------------------

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

show_help() {
    head -20 "$0" | tail -14
    exit 0
}

#------------------------------------------------------------------------------
# Parse Arguments
#------------------------------------------------------------------------------

while [[ $# -gt 0 ]]; do
    case $1 in
        --terraform-only)
            TERRAFORM_ONLY=true
            shift
            ;;
        --ansible-only)
            ANSIBLE_ONLY=true
            shift
            ;;
        --skip-apply)
            SKIP_APPLY=true
            shift
            ;;
        --help)
            show_help
            ;;
        *)
            log_error "Unknown option: $1"
            show_help
            ;;
    esac
done

#------------------------------------------------------------------------------
# Check Prerequisites
#------------------------------------------------------------------------------

check_prerequisites() {
    log_info "Checking prerequisites..."
    
    local missing_tools=()
    
    # Check Terraform
    if ! command -v terraform &> /dev/null; then
        missing_tools+=("terraform")
    else
        log_success "Terraform $(terraform version -json | jq -r '.terraform_version') found"
    fi
    
    # Check Ansible
    if ! command -v ansible &> /dev/null; then
        missing_tools+=("ansible")
    else
        log_success "Ansible $(ansible --version | head -1 | awk '{print $2}') found"
    fi
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        missing_tools+=("aws-cli")
    else
        log_success "AWS CLI $(aws --version | awk '{print $1}' | cut -d'/' -f2) found"
    fi
    
    # Check jq
    if ! command -v jq &> /dev/null; then
        missing_tools+=("jq")
    else
        log_success "jq found"
    fi
    
    # Check if AWS credentials are configured
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS credentials not configured. Run 'aws configure'"
        exit 1
    fi
    log_success "AWS credentials configured"
    
    if [ ${#missing_tools[@]} -gt 0 ]; then
        log_error "Missing required tools: ${missing_tools[*]}"
        log_info "Please install the missing tools and try again."
        exit 1
    fi
    
    log_success "All prerequisites satisfied"
}

#------------------------------------------------------------------------------
# Terraform Setup
#------------------------------------------------------------------------------

run_terraform() {
    log_info "Running Terraform..."
    cd "$TERRAFORM_DIR"
    
    # Check for tfvars file
    if [ ! -f "terraform.tfvars" ]; then
        if [ -f "terraform.tfvars.example" ]; then
            log_warning "terraform.tfvars not found. Please create it from terraform.tfvars.example"
            log_info "cp terraform.tfvars.example terraform.tfvars"
            log_info "Edit terraform.tfvars with your values"
            exit 1
        fi
    fi
    
    # Initialize Terraform
    log_info "Initializing Terraform..."
    terraform init
    
    # Validate configuration
    log_info "Validating Terraform configuration..."
    terraform validate
    
    # Plan
    log_info "Creating Terraform plan..."
    terraform plan -out=tfplan
    
    if [ "$SKIP_APPLY" = true ]; then
        log_warning "Skipping Terraform apply (--skip-apply flag set)"
        return
    fi
    
    # Apply
    log_info "Applying Terraform configuration..."
    read -p "Do you want to apply the Terraform plan? (yes/no): " confirm
    if [ "$confirm" = "yes" ]; then
        terraform apply tfplan
        log_success "Terraform apply completed"
    else
        log_warning "Terraform apply cancelled"
        exit 0
    fi
    
    cd "$PROJECT_ROOT"
}

#------------------------------------------------------------------------------
# Generate Ansible Inventory
#------------------------------------------------------------------------------

generate_inventory() {
    log_info "Generating Ansible inventory from Terraform outputs..."
    cd "$TERRAFORM_DIR"
    
    # Get outputs
    local bastion_ip=$(terraform output -raw bastion_public_ip)
    local master_ip=$(terraform output -raw master_private_ip)
    local worker_ips=$(terraform output -json worker_private_ips | jq -r '.[]')
    local mongodb_ip=$(terraform output -raw mongodb_private_ip)
    
    # Generate inventory file
    local inventory_file="$ANSIBLE_DIR/inventory/hosts.ini"
    
    cat > "$inventory_file" << EOF
#==============================================================================
# Auto-generated Ansible Inventory
# Generated at: $(date)
#==============================================================================

[bastion]
bastion ansible_host=${bastion_ip} ansible_user=ubuntu

[master]
k8s-master ansible_host=${master_ip} ansible_user=ubuntu

[workers]
EOF

    local worker_count=1
    for ip in $worker_ips; do
        echo "k8s-worker-${worker_count} ansible_host=${ip} ansible_user=ubuntu" >> "$inventory_file"
        ((worker_count++))
    done

    cat >> "$inventory_file" << EOF

[mongodb]
mongodb-server ansible_host=${mongodb_ip} ansible_user=ubuntu

[k8s_cluster:children]
master
workers

[private:children]
master
workers
mongodb

[all:vars]
ansible_ssh_private_key_file=~/.ssh/your-key.pem
ansible_ssh_common_args='-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null'

[private:vars]
ansible_ssh_common_args='-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ProxyCommand="ssh -W %h:%p -q ubuntu@${bastion_ip} -i ~/.ssh/your-key.pem"'
EOF

    log_success "Inventory file generated: $inventory_file"
    log_warning "Remember to update ansible_ssh_private_key_file with your actual key path"
    
    cd "$PROJECT_ROOT"
}

#------------------------------------------------------------------------------
# Wait for Instances
#------------------------------------------------------------------------------

wait_for_instances() {
    log_info "Waiting for instances to be ready..."
    
    cd "$TERRAFORM_DIR"
    local bastion_ip=$(terraform output -raw bastion_public_ip)
    cd "$PROJECT_ROOT"
    
    log_info "Waiting for bastion host to accept SSH connections..."
    local max_attempts=30
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        if ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 -o BatchMode=yes ubuntu@"$bastion_ip" exit 2>/dev/null; then
            log_success "Bastion host is ready"
            break
        fi
        log_info "Attempt $attempt/$max_attempts - Waiting..."
        sleep 10
        ((attempt++))
    done
    
    if [ $attempt -gt $max_attempts ]; then
        log_error "Timeout waiting for bastion host"
        exit 1
    fi
    
    # Give other instances time to boot
    log_info "Waiting additional 60 seconds for all instances to initialize..."
    sleep 60
}

#------------------------------------------------------------------------------
# Run Ansible Playbooks
#------------------------------------------------------------------------------

run_ansible() {
    log_info "Running Ansible playbooks..."
    cd "$ANSIBLE_DIR"
    
    local inventory="inventory/hosts.ini"
    
    if [ ! -f "$inventory" ]; then
        log_error "Inventory file not found: $inventory"
        log_info "Run Terraform first or generate inventory manually"
        exit 1
    fi
    
    # Playbook sequence
    local playbooks=(
        "playbooks/01-prerequisites.yml"
        "playbooks/02-init-cluster.yml"
        "playbooks/03-join-workers.yml"
        "playbooks/04-install-cni.yml"
        "playbooks/05-install-helm.yml"
        "playbooks/06-deploy-monitoring.yml"
        "playbooks/07-deploy-argocd.yml"
        "playbooks/08-setup-mongodb.yml"
    )
    
    for playbook in "${playbooks[@]}"; do
        log_info "Running $playbook..."
        ansible-playbook -i "$inventory" "$playbook"
        log_success "Completed $playbook"
    done
    
    log_success "All Ansible playbooks completed"
    cd "$PROJECT_ROOT"
}

#------------------------------------------------------------------------------
# Display Access Information
#------------------------------------------------------------------------------

display_access_info() {
    log_info "Fetching access information..."
    cd "$TERRAFORM_DIR"
    
    local alb_dns=$(terraform output -raw alb_dns_name)
    local bastion_ip=$(terraform output -raw bastion_public_ip)
    local master_ip=$(terraform output -raw master_private_ip)
    
    echo ""
    echo "=============================================================================="
    echo -e "${GREEN}Infrastructure Setup Complete!${NC}"
    echo "=============================================================================="
    echo ""
    echo "Access Information:"
    echo "-------------------"
    echo "Application URL:     http://${alb_dns}"
    echo "API URL:             http://${alb_dns}/api"
    echo "Grafana URL:         http://${alb_dns}/grafana"
    echo ""
    echo "SSH Access:"
    echo "-----------"
    echo "Bastion:   ssh -i ~/.ssh/your-key.pem ubuntu@${bastion_ip}"
    echo "Master:    ssh -i ~/.ssh/your-key.pem -J ubuntu@${bastion_ip} ubuntu@${master_ip}"
    echo ""
    echo "Next Steps:"
    echo "-----------"
    echo "1. Update backend-configmap.yaml with MongoDB IP"
    echo "2. Apply ArgoCD application: kubectl apply -f argocd/applications/mern-app.yaml"
    echo "3. Push your application images to DockerHub"
    echo "4. Access the application at http://${alb_dns}"
    echo ""
    echo "=============================================================================="
    
    cd "$PROJECT_ROOT"
}

#------------------------------------------------------------------------------
# Main
#------------------------------------------------------------------------------

main() {
    echo ""
    echo "=============================================================================="
    echo -e "${BLUE}MERN Infrastructure Setup${NC}"
    echo "=============================================================================="
    echo ""
    
    check_prerequisites
    
    if [ "$ANSIBLE_ONLY" = false ]; then
        run_terraform
        if [ "$SKIP_APPLY" = false ]; then
            generate_inventory
        fi
    fi
    
    if [ "$TERRAFORM_ONLY" = false ] && [ "$SKIP_APPLY" = false ]; then
        wait_for_instances
        run_ansible
    fi
    
    if [ "$SKIP_APPLY" = false ]; then
        display_access_info
    fi
}

main
