#!/bin/bash
#==============================================================================
# Script 05: Install Helm
#==============================================================================
# Installs Helm package manager on the master node.
# Adds common Helm repositories for Prometheus, Grafana, and ArgoCD.
#
# Usage: ./05-install-helm.sh
#
# Mirrors: ansible/playbooks/05-install-helm.yml
#==============================================================================

set -e

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source configuration and helpers
source "$SCRIPT_DIR/config.sh"
source "$SCRIPT_DIR/helpers.sh"

#------------------------------------------------------------------------------
# Helm Installation Script
#------------------------------------------------------------------------------
HELM_INSTALL_SCRIPT='
#!/bin/bash
set -e

export KUBECONFIG=/home/ubuntu/.kube/config

echo "==> Checking if Helm is already installed..."

if command -v helm &>/dev/null; then
    echo "Helm is already installed: $(helm version --short)"
else
    echo "==> Installing Helm..."
    curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
    echo "Helm installed: $(helm version --short)"
fi

echo "==> Adding Helm repositories..."

# Add Prometheus community repo
echo "Adding prometheus-community repo..."
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts 2>/dev/null || true

# Add Grafana repo
echo "Adding grafana repo..."
helm repo add grafana https://grafana.github.io/helm-charts 2>/dev/null || true

# Add ArgoCD repo
echo "Adding argo repo..."
helm repo add argo https://argoproj.github.io/argo-helm 2>/dev/null || true

echo "==> Updating Helm repositories..."
helm repo update

echo ""
echo "==> Helm repositories:"
helm repo list

echo ""
echo "==> Helm installation complete!"
'

#------------------------------------------------------------------------------
# Main Execution
#------------------------------------------------------------------------------

main() {
    log_header "Installing Helm Package Manager"
    
    # Validate required variables
    check_required_vars BASTION_IP MASTER_IP || exit 1
    validate_ssh_key || exit 1
    
    step_progress 1 2 "Installing Helm on Master ($MASTER_IP)"
    
    # Install Helm as root (for binary installation)
    ssh_exec "$MASTER_IP" "sudo bash -s" <<< "$HELM_INSTALL_SCRIPT"
    
    log_success "Helm installed"
    
    step_progress 2 2 "Configuring Helm for ubuntu user"
    
    # Also add repos for ubuntu user
    ssh_exec "$MASTER_IP" "bash -s" << 'EOF'
export KUBECONFIG=/home/ubuntu/.kube/config
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts 2>/dev/null || true
helm repo add grafana https://grafana.github.io/helm-charts 2>/dev/null || true
helm repo add argo https://argoproj.github.io/argo-helm 2>/dev/null || true
helm repo update
helm repo list
EOF
    
    log_success "Helm configured for ubuntu user"
    
    show_completion "Helm Installation"
    
    log_info "Helm is installed with the following repositories:"
    log_info "  - prometheus-community (Prometheus, Alertmanager)"
    log_info "  - grafana (Grafana, Loki)"
    log_info "  - argo (ArgoCD, Argo Workflows)"
    log_info ""
    log_info "Next step: Run 06-deploy-monitoring.sh to deploy the monitoring stack."
}

main "$@"
