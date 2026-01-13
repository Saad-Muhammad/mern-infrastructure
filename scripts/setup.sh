#!/bin/bash
#==============================================================================
# MERN Infrastructure Setup Script
#==============================================================================
# This script automates the complete infrastructure setup process:
# 1. Validates prerequisites
# 2. Runs Terraform to provision AWS infrastructure
# 3. Generates inventory from Terraform outputs
# 4. Runs configuration (Ansible or Bash scripts)
# 5. Displays access information
#
# Usage: ./scripts/setup.sh [options]
# Options:
#   --terraform-only    Only run Terraform
#   --ansible-only      Only run Ansible (requires existing inventory)
#   --bash-only         Only run Bash scripts (alternative to Ansible)
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

BASH_DIR="$SCRIPT_DIR/bash"

# Default options
TERRAFORM_ONLY=false
ANSIBLE_ONLY=false
BASH_ONLY=false
SKIP_APPLY=false
USE_BASH=false  # Use bash scripts instead of Ansible

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
        --bash-only)
            BASH_ONLY=true
            USE_BASH=true
            shift
            ;;
        --use-bash)
            USE_BASH=true
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
    
    # Check Terraform (skip if running config-only modes)
    if [ "$ANSIBLE_ONLY" = false ] && [ "$BASH_ONLY" = false ]; then
        if ! command -v terraform &> /dev/null; then
            missing_tools+=("terraform")
        else
            log_success "Terraform $(terraform version --json 2>/dev/null | grep -o '"terraform_version":"[^"]*' | cut -d'"' -f4 || terraform version | head -1 | awk '{print $2}') found"
        fi
    fi
    
    # Check Ansible (only if NOT using bash scripts)
    if [ "$USE_BASH" = false ] && [ "$BASH_ONLY" = false ]; then
        if ! command -v ansible &> /dev/null; then
            missing_tools+=("ansible")
        else
            log_success "Ansible $(ansible --version | head -1 | awk '{print $2}') found"
        fi
    else
        log_info "Using bash scripts - Ansible not required"
    fi
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        missing_tools+=("aws-cli")
    else
        log_success "AWS CLI $(aws --version | awk '{print $1}' | cut -d'/' -f2) found"
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

detect_ssh_key() {
    log_info "Detecting SSH key..."
    
    # If using bash scripts, source config.sh to get SSH_KEY_PATH
    if [ "$USE_BASH" = true ] || [ "$BASH_ONLY" = true ]; then
        if [ -f "$BASH_DIR/config.sh" ]; then
            source "$BASH_DIR/config.sh"
            if [ -n "$SSH_KEY_PATH" ] && [ -f "$SSH_KEY_PATH" ]; then
                log_success "Using SSH key from config.sh: $SSH_KEY_PATH"
                return
            fi
        fi
    fi
    
    # Check common locations
    local key_locations=(
        "/c/Users/User/Documents/AWS/aws-rsa-keys.pem"
        "$HOME/Documents/AWS/aws-rsa-keys.pem"
        "$HOME/.ssh/aws-rsa-keys.pem"
    )
    
    for key_path in "${key_locations[@]}"; do
        if [ -f "$key_path" ]; then
            SSH_KEY_PATH="$key_path"
            log_success "Found SSH key: $SSH_KEY_PATH"
            return
        fi
    done
    
    # Try to find key_name in terraform.tfvars
    if [ -f "$TERRAFORM_DIR/terraform.tfvars" ]; then
        local key_name=$(grep "key_name" "$TERRAFORM_DIR/terraform.tfvars" | head -1 | cut -d'=' -f2 | tr -d ' "')
        key_name=$(echo "$key_name" | xargs)
        
        if [ -n "$key_name" ]; then
            if [ -f "$HOME/.ssh/${key_name}.pem" ]; then
                SSH_KEY_PATH="$HOME/.ssh/${key_name}.pem"
                log_success "Found SSH key: $SSH_KEY_PATH"
                return
            elif [ -f "$HOME/.ssh/${key_name}" ]; then
                SSH_KEY_PATH="$HOME/.ssh/${key_name}"
                log_success "Found SSH key: $SSH_KEY_PATH"
                return
            fi
        fi
    fi
    
    SSH_KEY_PATH="$HOME/.ssh/your-key.pem"
    log_warning "Could not auto-detect key. Using default: $SSH_KEY_PATH"
    log_info "Set SSH_KEY_PATH in scripts/bash/config.sh or export SSH_KEY_PATH=..."
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
    
    # Get outputs (parsing JSON without jq)
    local bastion_ip=$(terraform output -raw bastion_public_ip)
    local master_ip=$(terraform output -raw master_private_ip)
    # Parse worker IPs - remove brackets, quotes, and convert to newlines
    local worker_ips=$(terraform output -json worker_private_ips | tr -d '[]"' | tr ',' '\n' | xargs)
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
ansible_ssh_private_key_file=${SSH_KEY_PATH}
ansible_ssh_common_args='-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null'

[private:vars]
ansible_ssh_common_args='-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ProxyCommand="ssh -W %h:%p -q ubuntu@${bastion_ip} -i ${SSH_KEY_PATH}"'
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
    
    local bastion_ip="${BASTION_IP}"
    
    # If BASTION_IP not set, try to get from Terraform
    if [ -z "$bastion_ip" ]; then
        if [ -d "$TERRAFORM_DIR" ]; then
            cd "$TERRAFORM_DIR"
            bastion_ip=$(terraform output -raw bastion_public_ip 2>/dev/null)
            cd "$PROJECT_ROOT"
        fi
    fi
    
    if [ -z "$bastion_ip" ]; then
        log_warning "Could not determine Bastion IP. Skipping connectivity check."
        return
    fi
    
    log_info "Waiting for bastion host ($bastion_ip) to accept SSH connections..."
    local max_attempts=30
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        # Try SSH, show error on failure if debug needed (removed 2>/dev/null for first attempt)
        if [ $attempt -eq 1 ]; then
             if ssh -i "$SSH_KEY_PATH" -o StrictHostKeyChecking=no -o ConnectTimeout=5 -o BatchMode=yes ubuntu@"$bastion_ip" exit; then
                log_success "Bastion host is ready"
                break
             else
                log_info "First attempt failed. Retrying..."
             fi
        else
             if ssh -i "$SSH_KEY_PATH" -o StrictHostKeyChecking=no -o ConnectTimeout=5 -o BatchMode=yes ubuntu@"$bastion_ip" exit 2>/dev/null; then
                log_success "Bastion host is ready"
                break
             fi
        fi

        log_info "Attempt $attempt/$max_attempts - Waiting..."
        sleep 10
        ((attempt++))
    done
    
    if [ $attempt -gt $max_attempts ]; then
        log_error "Timeout waiting for bastion host"
        log_info "Debug: Attempted to connect to ubuntu@$bastion_ip with key $SSH_KEY_PATH"
        log_info "Try connecting manually to verify: ssh -i \"$SSH_KEY_PATH\" ubuntu@$bastion_ip"
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
    export ANSIBLE_CONFIG="$ANSIBLE_DIR/ansible.cfg"
    
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
        ansible-playbook -i "inventory/hosts.ini" "$playbook"
        log_success "Completed $playbook"
    done
    
    log_success "All Ansible playbooks completed"
    cd "$PROJECT_ROOT"
}

#------------------------------------------------------------------------------
# Run Bash Scripts (Alternative to Ansible)
#------------------------------------------------------------------------------

run_bash() {
    log_info "Running Bash scripts for cluster configuration..."
    
    # Check if bash scripts directory exists
    if [ ! -d "$BASH_DIR" ]; then
        log_error "Bash scripts directory not found: $BASH_DIR"
        exit 1
    fi
    
    # Get outputs from Terraform
    cd "$TERRAFORM_DIR"
    export BASTION_IP=$(terraform output -raw bastion_public_ip)
    export MASTER_IP=$(terraform output -raw master_private_ip)
    # Parse worker IPs without jq - remove brackets and quotes, convert commas to spaces
    export WORKER_IPS=$(terraform output -json worker_private_ips 2>/dev/null | tr -d '[]"\n\r' | tr ',' ' ' | xargs)
    export MONGODB_IP=$(terraform output -raw mongodb_private_ip 2>/dev/null || echo "")
    export SSH_KEY_PATH="$SSH_KEY_PATH"
    
    log_info "Configuration for bash scripts:"
    echo "  BASTION_IP:  $BASTION_IP"
    echo "  MASTER_IP:   $MASTER_IP"
    echo "  WORKER_IPS:  $WORKER_IPS"
    echo "  MONGODB_IP:  ${MONGODB_IP:-<not configured>}"
    echo "  SSH_KEY:     $SSH_KEY_PATH"
    echo ""
    
    cd "$BASH_DIR"
    
    # Make scripts executable
    chmod +x *.sh
    
    # Run the master orchestration script
    ./run-all.sh
    
    log_success "All Bash scripts completed"
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
    echo "Bastion:   ssh -i ${SSH_KEY_PATH} ubuntu@${bastion_ip}"
    echo "Master:    ssh -i ${SSH_KEY_PATH} -J ubuntu@${bastion_ip} ubuntu@${master_ip}"
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
    detect_ssh_key
    
    # Handle --bash-only mode (skip Terraform, run bash scripts only)
    if [ "$BASH_ONLY" = true ]; then
        log_info "Running in BASH-ONLY mode"
        wait_for_instances
        run_bash
        display_access_info
        return
    fi
    
    # Handle --ansible-only mode (skip Terraform, run Ansible only)
    if [ "$ANSIBLE_ONLY" = true ]; then
        log_info "Running in ANSIBLE-ONLY mode"
        wait_for_instances
        run_ansible
        display_access_info
        return
    fi
    
    # Full setup: Terraform + Configuration
    run_terraform
    if [ "$SKIP_APPLY" = false ]; then
        generate_inventory
    fi
    
    if [ "$TERRAFORM_ONLY" = false ] && [ "$SKIP_APPLY" = false ]; then
        wait_for_instances
        
        # Choose configuration method
        if [ "$USE_BASH" = true ]; then
            log_info "Using Bash scripts for configuration (--use-bash flag)"
            run_bash
        else
            log_info "Using Ansible for configuration"
            run_ansible
        fi
    fi
    
    if [ "$SKIP_APPLY" = false ]; then
        display_access_info
    fi
}

main
