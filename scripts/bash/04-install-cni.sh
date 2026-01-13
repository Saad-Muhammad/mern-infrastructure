#!/bin/bash
#==============================================================================
# Script 04: Install CNI (Calico)
#==============================================================================
# Installs Calico CNI plugin for pod networking.
# Waits for all pods to be ready before completing.
#
# Usage: ./04-install-cni.sh
#
# Mirrors: ansible/playbooks/04-install-cni.yml
#==============================================================================

set -e

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source configuration and helpers
source "$SCRIPT_DIR/config.sh"
source "$SCRIPT_DIR/helpers.sh"

#------------------------------------------------------------------------------
# CNI Installation Script
#------------------------------------------------------------------------------
generate_cni_script() {
    local calico_version="$1"
    cat << EOF
#!/bin/bash
set -e

export KUBECONFIG=/home/ubuntu/.kube/config
CALICO_VERSION="$calico_version"
CALICO_MANIFEST_URL="https://raw.githubusercontent.com/projectcalico/calico/\${CALICO_VERSION}/manifests/calico.yaml"

echo "==> Checking if Calico is already installed..."

CALICO_PODS=\$(kubectl get pods -n kube-system -l k8s-app=calico-node -o name 2>/dev/null || echo "")

if [ -n "\$CALICO_PODS" ]; then
    echo "Calico is already installed. Checking status..."
else
    echo "==> Downloading Calico manifest (version: \$CALICO_VERSION)..."
    curl -fsSL "\$CALICO_MANIFEST_URL" -o /tmp/calico.yaml
    
    echo "==> Applying Calico CNI manifest..."
    kubectl apply -f /tmp/calico.yaml
    
    echo "==> Calico manifest applied!"
fi

echo "==> Waiting for Calico pods to be ready..."

for i in {1..10}; do
    if kubectl wait --for=condition=ready pods -l k8s-app=calico-node -n kube-system --timeout=60s 2>/dev/null; then
        echo "Calico pods are ready!"
        break
    fi
    echo "Waiting for Calico pods... (attempt \$i/10)"
    sleep 30
done

echo "==> Waiting for CoreDNS pods to be ready..."

for i in {1..10}; do
    if kubectl wait --for=condition=ready pods -l k8s-app=kube-dns -n kube-system --timeout=60s 2>/dev/null; then
        echo "CoreDNS pods are ready!"
        break
    fi
    echo "Waiting for CoreDNS pods... (attempt \$i/10)"
    sleep 30
done

echo "==> Waiting for all nodes to be Ready..."

for i in {1..30}; do
    NODE_STATUS=\$(kubectl get nodes -o jsonpath='{.items[*].status.conditions[?(@.type=="Ready")].status}')
    if [[ "\$NODE_STATUS" != *"False"* ]] && [[ "\$NODE_STATUS" != *"Unknown"* ]] && [ -n "\$NODE_STATUS" ]; then
        echo "All nodes are Ready!"
        break
    fi
    echo "Waiting for nodes to be Ready... (attempt \$i/30)"
    sleep 10
done

echo ""
echo "==> Final cluster status:"
kubectl get nodes -o wide

echo ""
echo "==> Kube-system pods:"
kubectl get pods -n kube-system -o wide
EOF
}

#------------------------------------------------------------------------------
# Main Execution
#------------------------------------------------------------------------------

main() {
    log_header "Installing Calico CNI"
    
    # Validate required variables
    check_required_vars BASTION_IP MASTER_IP CALICO_VERSION || exit 1
    validate_ssh_key || exit 1
    
    step_progress 1 2 "Installing Calico CNI on cluster"
    
    CNI_SCRIPT=$(generate_cni_script "$CALICO_VERSION")
    ssh_exec "$MASTER_IP" "bash -s" <<< "$CNI_SCRIPT"
    
    log_success "Calico CNI installed"
    
    step_progress 2 2 "Verifying cluster networking"
    
    # Final verification
    ssh_exec "$MASTER_IP" "kubectl get nodes -o wide"
    
    show_completion "Calico CNI Installation"
    
    log_info "All nodes should now show 'Ready' status."
    log_info "Pod networking is configured with Calico."
    log_info ""
    log_info "Next step: Run 05-install-helm.sh to install Helm."
}

main "$@"
