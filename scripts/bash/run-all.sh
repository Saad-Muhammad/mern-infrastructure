#!/bin/bash
#==============================================================================
# MERN Infrastructure - Run All Scripts
#==============================================================================
# Master orchestration script that runs all bash scripts in sequence.
# This replaces the Ansible playbook execution from setup.sh.
#
# Usage: ./run-all.sh [options]
# Options:
#   --from <step>      Start from a specific step (1-8)
#   --only <step>      Run only a specific step
#   --skip-mongodb     Skip MongoDB setup
#   --dry-run          Show what would be executed without running
#   --help             Show this help message
#
# Environment Variables (required):
#   BASTION_IP         Public IP of bastion host
#   MASTER_IP          Private IP of master node
#   WORKER_IPS         Space-separated list of worker private IPs
#   MONGODB_IP         Private IP of MongoDB server (optional)
#   SSH_KEY_PATH       Path to SSH private key
#==============================================================================

set -e

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source configuration and helpers
source "$SCRIPT_DIR/config.sh"
source "$SCRIPT_DIR/helpers.sh"

# Default options
FROM_STEP=1
ONLY_STEP=""
SKIP_MONGODB=false
DRY_RUN=false

#------------------------------------------------------------------------------
# Script Information
#------------------------------------------------------------------------------
SCRIPTS=(
    "01-prerequisites.sh|Install Docker, containerd, and K8s components on all nodes"
    "02-init-cluster.sh|Initialize Kubernetes cluster on master node"
    "03-join-workers.sh|Join worker nodes to the cluster"
    "04-install-cni.sh|Install Calico CNI for pod networking"
    "05-install-helm.sh|Install Helm package manager"
    "06-deploy-monitoring.sh|Deploy Prometheus and Grafana monitoring stack"
    "07-deploy-argocd.sh|Deploy ArgoCD for GitOps"
    "08-setup-mongodb.sh|Setup MongoDB database server"
)

#------------------------------------------------------------------------------
# Parse Arguments
#------------------------------------------------------------------------------

show_help() {
    head -20 "$0" | tail -16
    echo ""
    echo "Steps:"
    for i in "${!SCRIPTS[@]}"; do
        IFS='|' read -r script desc <<< "${SCRIPTS[$i]}"
        echo "  $((i+1)). $script - $desc"
    done
    exit 0
}

while [[ $# -gt 0 ]]; do
    case $1 in
        --from)
            FROM_STEP="$2"
            shift 2
            ;;
        --only)
            ONLY_STEP="$2"
            shift 2
            ;;
        --skip-mongodb)
            SKIP_MONGODB=true
            shift
            ;;
        --dry-run)
            DRY_RUN=true
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
# Validation
#------------------------------------------------------------------------------

validate_environment() {
    log_info "Validating environment..."
    
    local errors=()
    
    # Check required variables
    [ -z "$BASTION_IP" ] && errors+=("BASTION_IP is not set")
    [ -z "$MASTER_IP" ] && errors+=("MASTER_IP is not set")
    [ -z "$SSH_KEY_PATH" ] && errors+=("SSH_KEY_PATH is not set")
    
    # Check SSH key exists
    [ ! -f "$SSH_KEY_PATH" ] && errors+=("SSH key not found: $SSH_KEY_PATH")
    
    if [ ${#errors[@]} -gt 0 ]; then
        log_error "Environment validation failed:"
        for err in "${errors[@]}"; do
            echo "  - $err"
        done
        echo ""
        echo "Please set the required environment variables or update config.sh"
        echo ""
        echo "Example:"
        echo "  export BASTION_IP=1.2.3.4"
        echo "  export MASTER_IP=10.0.1.10"
        echo "  export WORKER_IPS=\"10.0.1.11 10.0.1.12\""
        echo "  export MONGODB_IP=10.0.2.10"
        echo "  export SSH_KEY_PATH=~/.ssh/your-key.pem"
        return 1
    fi
    
    log_success "Environment validation passed"
    
    echo ""
    echo "Configuration:"
    echo "  Bastion IP:    $BASTION_IP"
    echo "  Master IP:     $MASTER_IP"
    echo "  Worker IPs:    ${WORKER_IPS:-<none>}"
    echo "  MongoDB IP:    ${MONGODB_IP:-<none>}"
    echo "  SSH Key:       $SSH_KEY_PATH"
    echo ""
    
    return 0
}

#------------------------------------------------------------------------------
# Run Scripts
#------------------------------------------------------------------------------

run_script() {
    local step="$1"
    local script="$2"
    local description="$3"
    
    log_header "Step $step: $description"
    
    if [ "$DRY_RUN" = true ]; then
        log_info "[DRY RUN] Would execute: $SCRIPT_DIR/$script"
        return 0
    fi
    
    # Check if script exists
    if [ ! -f "$SCRIPT_DIR/$script" ]; then
        log_error "Script not found: $SCRIPT_DIR/$script"
        return 1
    fi
    
    # Make script executable
    chmod +x "$SCRIPT_DIR/$script"
    
    # Run the script
    "$SCRIPT_DIR/$script"
    
    log_success "Step $step completed!"
}

#------------------------------------------------------------------------------
# Main Execution
#------------------------------------------------------------------------------

main() {
    echo ""
    echo "=============================================================================="
    echo -e "${BLUE}MERN Infrastructure - Bash Script Orchestrator${NC}"
    echo "=============================================================================="
    echo ""
    
    # Validate environment
    validate_environment || exit 1
    
    # Determine which steps to run
    local steps_to_run=()
    
    if [ -n "$ONLY_STEP" ]; then
        steps_to_run=("$ONLY_STEP")
    else
        for i in $(seq $FROM_STEP 8); do
            steps_to_run+=("$i")
        done
    fi
    
    log_info "Steps to run: ${steps_to_run[*]}"
    echo ""
    
    # Run selected scripts
    for step in "${steps_to_run[@]}"; do
        local index=$((step - 1))
        
        if [ $index -lt 0 ] || [ $index -ge ${#SCRIPTS[@]} ]; then
            log_error "Invalid step number: $step"
            continue
        fi
        
        IFS='|' read -r script description <<< "${SCRIPTS[$index]}"
        
        # Skip MongoDB if requested
        if [ "$SKIP_MONGODB" = true ] && [ "$script" = "08-setup-mongodb.sh" ]; then
            log_warning "Skipping MongoDB setup (--skip-mongodb flag set)"
            continue
        fi
        
        run_script "$step" "$script" "$description"
    done
    
    #--------------------------------------------------------------------------
    # Display summary
    #--------------------------------------------------------------------------
    echo ""
    echo "=============================================================================="
    echo -e "${GREEN}All Steps Completed Successfully!${NC}"
    echo "=============================================================================="
    echo ""
    echo "Your MERN infrastructure is now ready!"
    echo ""
    echo "Access Information:"
    echo "-------------------"
    
    # Get worker IP for access info
    IFS=' ' read -ra WORKER_ARRAY <<< "$WORKER_IPS"
    local access_ip="${WORKER_ARRAY[0]:-$MASTER_IP}"
    
    echo "  Grafana:     http://$access_ip:$GRAFANA_NODEPORT"
    echo "               Username: admin / Password: $GRAFANA_ADMIN_PASSWORD"
    echo ""
    echo "  ArgoCD:      https://$access_ip:$ARGOCD_NODEPORT"
    echo "               Username: admin"
    echo "               Password: Check $SCRIPT_DIR/argocd-credentials.txt"
    echo ""
    
    if [ -n "$MONGODB_IP" ]; then
        echo "  MongoDB:     mongodb://$MONGODB_APP_USER:***@$MONGODB_IP:$MONGODB_PORT/$MONGODB_APP_DATABASE"
        echo ""
    fi
    
    echo "SSH Access:"
    echo "-----------"
    echo "  Bastion:     ssh -i $SSH_KEY_PATH ubuntu@$BASTION_IP"
    echo "  Master:      ssh -i $SSH_KEY_PATH -J ubuntu@$BASTION_IP ubuntu@$MASTER_IP"
    echo ""
    echo "Next Steps:"
    echo "-----------"
    echo "  1. Update backend-configmap.yaml with MongoDB IP"
    echo "  2. Apply ArgoCD application: kubectl apply -f argocd/applications/mern-app.yaml"
    echo "  3. Push your application images to DockerHub"
    echo ""
}

main "$@"
