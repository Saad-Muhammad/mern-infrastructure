#!/bin/bash
#==============================================================================
# Script 03: Join Worker Nodes
#==============================================================================
# Joins worker nodes to the Kubernetes cluster using the join command
# generated during cluster initialization.
#
# Usage: ./03-join-workers.sh
#
# Mirrors: ansible/playbooks/03-join-workers.yml
#==============================================================================

set -e

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source configuration and helpers
source "$SCRIPT_DIR/config.sh"
source "$SCRIPT_DIR/helpers.sh"

#------------------------------------------------------------------------------
# Worker Join Script
#------------------------------------------------------------------------------
generate_join_script() {
    local join_command="$1"
    cat << EOF
#!/bin/bash
set -e

echo "==> Checking if node is already joined to cluster..."

if [ -f /etc/kubernetes/kubelet.conf ]; then
    echo "Node is already joined to the cluster. Skipping."
    exit 0
fi

echo "==> Joining node to cluster..."
$join_command

echo "==> Ensuring kubelet is running..."
systemctl enable kubelet
systemctl start kubelet

echo "==> Node joined successfully!"
EOF
}

#------------------------------------------------------------------------------
# Main Execution
#------------------------------------------------------------------------------

main() {
    log_header "Joining Worker Nodes to Cluster"
    
    # Validate required variables
    check_required_vars BASTION_IP MASTER_IP WORKER_IPS || exit 1
    validate_ssh_key || exit 1
    
    # Convert worker IPs string to array
    IFS=' ' read -ra WORKER_ARRAY <<< "$WORKER_IPS"
    
    if [ ${#WORKER_ARRAY[@]} -eq 0 ]; then
        log_warning "No worker IPs configured. Nothing to do."
        exit 0
    fi
    
    local total_steps=$((${#WORKER_ARRAY[@]} + 2))
    local current_step=0
    
    #--------------------------------------------------------------------------
    # Get join command from master
    #--------------------------------------------------------------------------
    #--------------------------------------------------------------------------
    # Get join command from master
    #--------------------------------------------------------------------------
    current_step=$((current_step + 1))
    step_progress $current_step $total_steps "Getting join command from Master ($MASTER_IP)"
    
    # Try to get from saved file first, otherwise generate new one
    local join_command=""
    if [ -f "$SCRIPT_DIR/join_command.sh" ]; then
        join_command=$(cat "$SCRIPT_DIR/join_command.sh")
        log_info "Using saved join command from previous run"
    else
        join_command=$(ssh_exec "$MASTER_IP" "sudo kubeadm token create --print-join-command")
        log_info "Generated new join command from master"
    fi
    
    log_success "Join command retrieved"
    log_info "Command: $join_command"
    
    #--------------------------------------------------------------------------
    # Join each worker node
    #--------------------------------------------------------------------------
    local worker_num=1
    for worker_ip in "${WORKER_ARRAY[@]}"; do
        current_step=$((current_step + 1))
        step_progress $current_step $total_steps "Joining Worker $worker_num ($worker_ip) to cluster"
        
        JOIN_SCRIPT=$(generate_join_script "$join_command")
        remote_script_sudo "$worker_ip" "$JOIN_SCRIPT"
        
        log_success "Worker $worker_num joined to cluster"
        worker_num=$((worker_num + 1))
    done
    
    #--------------------------------------------------------------------------
    # Verify all nodes are registered
    #--------------------------------------------------------------------------
    current_step=$((current_step + 1))
    step_progress $current_step $total_steps "Verifying cluster nodes"
    
    log_info "Waiting for all nodes to be registered..."
    sleep 30  # Give nodes time to register
    
    # Check nodes on master
    ssh_exec "$MASTER_IP" "kubectl get nodes -o wide"
    
    show_completion "Worker Nodes Join"
    
    local expected_nodes=$((1 + ${#WORKER_ARRAY[@]}))
    log_info "Expected nodes in cluster: $expected_nodes (1 master + ${#WORKER_ARRAY[@]} workers)"
    log_info ""
    log_info "Note: Nodes may show 'NotReady' until CNI is installed."
    log_info "Next step: Run 04-install-cni.sh to install Calico CNI."
}

main "$@"
