#!/bin/bash
#==============================================================================
# Script 06: Deploy Monitoring Stack
#==============================================================================
# Deploys Prometheus and Grafana using kube-prometheus-stack Helm chart.
# Configures Grafana with NodePort for external access.
#
# Usage: ./06-deploy-monitoring.sh
#
# Mirrors: ansible/playbooks/06-deploy-monitoring.yml
#==============================================================================

set -e

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source configuration and helpers
source "$SCRIPT_DIR/config.sh"
source "$SCRIPT_DIR/helpers.sh"

#------------------------------------------------------------------------------
# Monitoring Deployment Script
#------------------------------------------------------------------------------
generate_monitoring_script() {
    local grafana_password="$1"
    local grafana_nodeport="$2"
    local prometheus_retention="$3"
    local prometheus_storage="$4"
    local use_persistence="$5"
    
    local prometheus_storage_config=""
    if [ "$use_persistence" = "true" ]; then
        prometheus_storage_config="    storageSpec:
      volumeClaimTemplate:
        spec:
          accessModes: [\"ReadWriteOnce\"]
          resources:
            requests:
              storage: ${prometheus_storage}"
    else
        prometheus_storage_config="    # Ephemeral storage used (no storageSpec)"
    fi

    local alertmanager_storage_config=""
    if [ "$use_persistence" = "true" ]; then
        alertmanager_storage_config="  alertmanagerSpec:
    storage:
      volumeClaimTemplate:
        spec:
          accessModes: [\"ReadWriteOnce\"]
          resources:
            requests:
              storage: 10Gi"
    else
        alertmanager_storage_config="  # alertmanagerSpec omitted for ephemeral storage"
    fi
    
    cat << EOF
#!/bin/bash
set -e

export KUBECONFIG=/home/ubuntu/.kube/config

MONITORING_NAMESPACE="monitoring"
PROMETHEUS_STACK_RELEASE="prometheus-stack"

echo "==> Creating monitoring namespace..."
kubectl create namespace \$MONITORING_NAMESPACE 2>/dev/null || echo "Namespace already exists"

echo "==> Creating Prometheus values file..."
cat > /tmp/prometheus-values.yaml << 'VALUES'
# Grafana Configuration
grafana:
  enabled: true
  adminPassword: "${grafana_password}"
  service:
    type: NodePort
    nodePort: ${grafana_nodeport}
  ingress:
    enabled: false
  # Root URL for proper subpath routing
  grafana.ini:
    server:
      root_url: "%(protocol)s://%(domain)s/grafana"
      serve_from_sub_path: true

# Prometheus Configuration
prometheus:
  prometheusSpec:
    retention: ${prometheus_retention}
${prometheus_storage_config}
    serviceMonitorSelectorNilUsesHelmValues: false
    podMonitorSelectorNilUsesHelmValues: false
  service:
    type: ClusterIP

# AlertManager Configuration
alertmanager:
  enabled: true
${alertmanager_storage_config}

# Node Exporter
nodeExporter:
  enabled: true

# Node Exporter
nodeExporter:
  enabled: true

# Kube State Metrics
kubeStateMetrics:
  enabled: true
VALUES

echo "==> Checking if prometheus-stack is already installed..."
INSTALLED=\$(helm list -n \$MONITORING_NAMESPACE -q | grep -w "\$PROMETHEUS_STACK_RELEASE" || echo "")

if [ -z "\$INSTALLED" ]; then
    echo "==> Installing kube-prometheus-stack Helm chart..."
    helm upgrade --install \$PROMETHEUS_STACK_RELEASE \
        prometheus-community/kube-prometheus-stack \
        --namespace \$MONITORING_NAMESPACE \
        --values /tmp/prometheus-values.yaml \
        --wait \
        --timeout 10m
else
    echo "prometheus-stack is already installed. Upgrading..."
    helm upgrade \$PROMETHEUS_STACK_RELEASE \
        prometheus-community/kube-prometheus-stack \
        --namespace \$MONITORING_NAMESPACE \
        --values /tmp/prometheus-values.yaml \
        --wait \
        --timeout 10m
fi

echo "==> Waiting for Prometheus pods to be ready..."
for i in {1..10}; do
    if kubectl wait --for=condition=ready pods -l app.kubernetes.io/name=prometheus -n \$MONITORING_NAMESPACE --timeout=60s 2>/dev/null; then
        echo "Prometheus pods are ready!"
        break
    fi
    echo "Waiting for Prometheus pods... (attempt \$i/10)"
    sleep 30
done

echo "==> Waiting for Grafana pods to be ready..."
for i in {1..10}; do
    if kubectl wait --for=condition=ready pods -l app.kubernetes.io/name=grafana -n \$MONITORING_NAMESPACE --timeout=60s 2>/dev/null; then
        echo "Grafana pods are ready!"
        break
    fi
    echo "Waiting for Grafana pods... (attempt \$i/10)"
    sleep 30
done

echo ""
echo "==> Monitoring pods:"
kubectl get pods -n \$MONITORING_NAMESPACE -o wide

echo ""
echo "==> Monitoring services:"
kubectl get svc -n \$MONITORING_NAMESPACE

echo ""
echo "=============================================="
echo "Monitoring Stack Deployed Successfully!"
echo "=============================================="
echo ""
echo "Grafana Access:"
echo "  URL: http://<WORKER_IP>:${grafana_nodeport}"
echo "  Username: admin"
echo "  Password: ${grafana_password}"
echo ""
EOF
}

#------------------------------------------------------------------------------
# Main Execution
#------------------------------------------------------------------------------

main() {
    log_header "Deploying Monitoring Stack (Prometheus + Grafana)"
    
    # Validate required variables
    check_required_vars BASTION_IP MASTER_IP GRAFANA_ADMIN_PASSWORD GRAFANA_NODEPORT || exit 1
    validate_ssh_key || exit 1
    
    # Check for storage class (default or any)
    log_info "Checking for StorageClass..."
    if ssh_exec "$MASTER_IP" "kubectl get sc -o name" | grep -q "storageclass"; then
        log_success "StorageClass found. Using persistence."
        USE_PERSISTENCE="true"
    else
        log_warning "No StorageClass found. Disabling persistence (ephemeral storage)."
        USE_PERSISTENCE="false"
    fi
    
    step_progress 1 2 "Deploying kube-prometheus-stack on cluster"
    
    MONITORING_SCRIPT=$(generate_monitoring_script \
        "$GRAFANA_ADMIN_PASSWORD" \
        "$GRAFANA_NODEPORT" \
        "$PROMETHEUS_RETENTION" \
        "$PROMETHEUS_STORAGE_SIZE" \
        "$USE_PERSISTENCE")
    
    ssh_exec "$MASTER_IP" "bash -s" <<< "$MONITORING_SCRIPT"
    
    log_success "Monitoring stack deployed"
    
    step_progress 2 2 "Verifying monitoring deployment"
    
    ssh_exec "$MASTER_IP" "kubectl get pods -n monitoring"
    
    show_completion "Monitoring Stack Deployment"
    
    log_info "Prometheus and Grafana are now deployed."
    log_info "Access Grafana at: http://<WORKER_IP>:$GRAFANA_NODEPORT"
    log_info "Grafana credentials: admin / $GRAFANA_ADMIN_PASSWORD"
    log_info ""
    log_info "Next step: Run 07-deploy-argocd.sh to deploy ArgoCD."
}

main "$@"
