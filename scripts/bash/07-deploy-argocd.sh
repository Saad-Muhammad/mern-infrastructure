#!/bin/bash
#==============================================================================
# Script 07: Deploy ArgoCD
#==============================================================================
# Deploys ArgoCD for GitOps-based continuous deployment.
# Retrieves admin password for initial access.
#
# Usage: ./07-deploy-argocd.sh
#
# Mirrors: ansible/playbooks/07-deploy-argocd.yml
#==============================================================================

set -e

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source configuration and helpers
source "$SCRIPT_DIR/config.sh"
source "$SCRIPT_DIR/helpers.sh"

#------------------------------------------------------------------------------
# ArgoCD Deployment Script
#------------------------------------------------------------------------------
generate_argocd_script() {
    local argocd_nodeport="$1"
    
    cat << EOF
#!/bin/bash
set -e

export KUBECONFIG=/home/ubuntu/.kube/config

ARGOCD_NAMESPACE="argocd"
ARGOCD_MANIFEST_URL="https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml"

echo "==> Creating ArgoCD namespace..."
kubectl create namespace \$ARGOCD_NAMESPACE 2>/dev/null || echo "Namespace already exists"

echo "==> Checking if ArgoCD is already installed..."
ARGOCD_CHECK=\$(kubectl get deployment argocd-server -n \$ARGOCD_NAMESPACE 2>/dev/null || echo "")

if [ -z "\$ARGOCD_CHECK" ]; then
    echo "==> Installing ArgoCD from manifest..."
    kubectl apply -n \$ARGOCD_NAMESPACE -f \$ARGOCD_MANIFEST_URL
else
    echo "ArgoCD is already installed."
fi

echo "==> Waiting for ArgoCD server deployment to be ready..."
for i in {1..10}; do
    if kubectl rollout status deployment/argocd-server -n \$ARGOCD_NAMESPACE --timeout=60s 2>/dev/null; then
        echo "ArgoCD server is ready!"
        break
    fi
    echo "Waiting for ArgoCD server... (attempt \$i/10)"
    sleep 30
done

echo "==> Waiting for ArgoCD repo server to be ready..."
kubectl rollout status deployment/argocd-repo-server -n \$ARGOCD_NAMESPACE --timeout=300s || true

echo "==> Waiting for ArgoCD application controller to be ready..."
kubectl rollout status deployment/argocd-applicationset-controller -n \$ARGOCD_NAMESPACE --timeout=300s 2>/dev/null || true

echo "==> Patching ArgoCD server to NodePort..."
kubectl patch svc argocd-server -n \$ARGOCD_NAMESPACE \
    -p '{"spec": {"type": "NodePort", "ports": [{"name": "http", "port": 80, "targetPort": 8080, "nodePort": ${argocd_nodeport}}, {"name": "https", "port": 443, "targetPort": 8080}]}}' \
    2>/dev/null || echo "Service already patched or patch failed"

echo "==> Getting ArgoCD admin initial password..."
ARGOCD_PASSWORD_BASE64=\$(kubectl -n \$ARGOCD_NAMESPACE get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" 2>/dev/null || echo "")

if [ -n "\$ARGOCD_PASSWORD_BASE64" ]; then
    ARGOCD_PASSWORD=\$(echo "\$ARGOCD_PASSWORD_BASE64" | base64 -d)
else
    ARGOCD_PASSWORD="<unable to retrieve - may have been deleted>"
fi

echo ""
echo "==> ArgoCD pods:"
kubectl get pods -n \$ARGOCD_NAMESPACE

echo ""
echo "==> ArgoCD services:"
kubectl get svc -n \$ARGOCD_NAMESPACE

echo ""
echo "=============================================="
echo "ArgoCD Deployed Successfully!"
echo "=============================================="
echo ""
echo "Access Information:"
echo "  URL: https://<WORKER_IP>:${argocd_nodeport}"
echo "  Username: admin"
echo "  Password: \$ARGOCD_PASSWORD"
echo ""
echo "To access via CLI:"
echo "  argocd login <WORKER_IP>:${argocd_nodeport} --username admin --password '\$ARGOCD_PASSWORD' --insecure"
echo ""

# Save credentials to file
cat > /home/ubuntu/argocd-credentials.txt << CREDS
ArgoCD Credentials
==================
Username: admin
Password: \$ARGOCD_PASSWORD
URL: https://<WORKER_IP>:${argocd_nodeport}
CREDS
chmod 600 /home/ubuntu/argocd-credentials.txt
echo "Credentials saved to /home/ubuntu/argocd-credentials.txt"
EOF
}

#------------------------------------------------------------------------------
# Main Execution
#------------------------------------------------------------------------------

main() {
    log_header "Deploying ArgoCD"
    
    # Validate required variables
    check_required_vars BASTION_IP MASTER_IP ARGOCD_NODEPORT || exit 1
    validate_ssh_key || exit 1
    
    step_progress 1 2 "Deploying ArgoCD on cluster"
    
    ARGOCD_SCRIPT=$(generate_argocd_script "$ARGOCD_NODEPORT")
    ssh_exec "$MASTER_IP" "bash -s" <<< "$ARGOCD_SCRIPT"
    
    log_success "ArgoCD deployed"
    
    step_progress 2 2 "Retrieving ArgoCD credentials"
    
    # Get the password
    ARGOCD_PASSWORD=$(ssh_exec "$MASTER_IP" "kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' 2>/dev/null | base64 -d" 2>/dev/null || echo "")
    
    if [ -n "$ARGOCD_PASSWORD" ]; then
        # Save credentials locally
        local creds_file="$SCRIPT_DIR/argocd-credentials.txt"
        cat > "$creds_file" << EOF
ArgoCD Credentials
==================
Username: admin
Password: $ARGOCD_PASSWORD
URL: https://<WORKER_IP>:$ARGOCD_NODEPORT
EOF
        chmod 600 "$creds_file"
        log_success "Credentials saved to: $creds_file"
    fi
    
    show_completion "ArgoCD Deployment"
    
    log_info "ArgoCD is now deployed."
    log_info "Access ArgoCD at: https://<WORKER_IP>:$ARGOCD_NODEPORT"
    log_info "Username: admin"
    [ -n "$ARGOCD_PASSWORD" ] && log_info "Password: $ARGOCD_PASSWORD"
    log_info ""
    log_info "Next step: Run 08-setup-mongodb.sh to set up MongoDB."
}

main "$@"
