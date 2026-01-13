#!/bin/bash
#==============================================================================
# Script 02: Initialize Kubernetes Cluster
#==============================================================================
# Initializes the Kubernetes cluster on the master node using kubeadm.
# Configures kubectl for the ubuntu user and generates join command.
#
# Usage: ./02-init-cluster.sh
#
# Mirrors: ansible/playbooks/02-init-cluster.yml
#==============================================================================

set -e

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source configuration and helpers
source "$SCRIPT_DIR/config.sh"
source "$SCRIPT_DIR/helpers.sh"

#------------------------------------------------------------------------------
# Cluster Initialization Script
#------------------------------------------------------------------------------
generate_init_script() {
    local pod_cidr="$1"
    cat << 'EOF'
#!/bin/bash
set -e

POD_NETWORK_CIDR="$1"

echo "==> Checking if cluster is already initialized..."

if [ -f /etc/kubernetes/admin.conf ]; then
    echo "Cluster is already initialized. Skipping kubeadm init."
else
    echo "==> Getting master node private IP..."
    MASTER_IP=$(hostname -I | awk '{print $1}')
    echo "Master IP: $MASTER_IP"
    
    echo "==> Initializing Kubernetes cluster with kubeadm..."
    kubeadm init \
        --pod-network-cidr="$POD_NETWORK_CIDR" \
        --apiserver-advertise-address="$MASTER_IP" \
        --control-plane-endpoint="$MASTER_IP:6443" \
        --upload-certs
    
    echo "==> Cluster initialized successfully!"
fi

echo "==> Configuring kubectl for ubuntu user..."

# Create .kube directory for ubuntu user
mkdir -p /home/ubuntu/.kube
cp /etc/kubernetes/admin.conf /home/ubuntu/.kube/config
chown -R ubuntu:ubuntu /home/ubuntu/.kube
chmod 600 /home/ubuntu/.kube/config

echo "==> Generating join command..."

# Generate and save join command
JOIN_COMMAND=$(kubeadm token create --print-join-command)
echo "$JOIN_COMMAND" > /tmp/kubeadm_join_command.sh
chmod 600 /tmp/kubeadm_join_command.sh

echo ""
echo "Join command saved to /tmp/kubeadm_join_command.sh"
echo "Command: $JOIN_COMMAND"

echo "==> Waiting for API server to be ready..."

# Wait for API server
export KUBECONFIG=/home/ubuntu/.kube/config
for i in {1..30}; do
    if kubectl get nodes &>/dev/null; then
        echo "API server is ready!"
        break
    fi
    echo "Waiting for API server... (attempt $i/30)"
    sleep 10
done

echo ""
echo "==> Cluster status:"
kubectl get nodes
EOF
}

#------------------------------------------------------------------------------
# Main Execution
#------------------------------------------------------------------------------

main() {
    log_header "Initializing Kubernetes Cluster"
    
    # Validate required variables
    check_required_vars BASTION_IP MASTER_IP POD_NETWORK_CIDR || exit 1
    validate_ssh_key || exit 1
    
    step_progress 1 3 "Initializing cluster on Master ($MASTER_IP)"
    
    # Generate and run the initialization script
    INIT_SCRIPT=$(generate_init_script)
    ssh_exec "$MASTER_IP" "sudo bash -s '$POD_NETWORK_CIDR'" <<< "$INIT_SCRIPT"
    
    log_success "Cluster initialization complete"
    
    step_progress 2 3 "Retrieving join command"
    
    # Get the join command from master
    JOIN_COMMAND=$(ssh_exec "$MASTER_IP" "sudo cat /tmp/kubeadm_join_command.sh")
    
    # Save join command locally
    local join_file="$SCRIPT_DIR/join_command.sh"
    echo "$JOIN_COMMAND" > "$join_file"
    chmod 600 "$join_file"
    
    log_success "Join command saved to: $join_file"
    
    step_progress 3 3 "Verifying cluster status"
    
    # Verify cluster is working
    ssh_exec "$MASTER_IP" "kubectl get nodes"
    
    show_completion "Kubernetes Cluster Initialization"
    
    log_info "Master node is initialized and ready."
    log_info "Join command: $JOIN_COMMAND"
    log_info ""
    log_info "Next step: Run 03-join-workers.sh to join worker nodes."
}

main "$@"
