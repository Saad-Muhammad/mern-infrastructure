#!/bin/bash
#==============================================================================
# MERN Application Deployment Script
#==============================================================================
# This script helps deploy the MERN Todo application:
# 1. Build and push Docker images
# 2. Update Kubernetes manifests with new image tags
# 3. Apply manifests directly or trigger ArgoCD sync
#
# Usage: ./scripts/deploy.sh [options]
# Options:
#   --build          Build Docker images locally
#   --push           Push images to DockerHub
#   --apply          Apply Kubernetes manifests directly
#   --tag TAG        Tag to use for images (default: latest)
#   --registry REG   Docker registry (default: docker.io)
#   --help           Show this help message
#==============================================================================

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
APP_DIR="$(dirname "$PROJECT_ROOT")/todo-app"
K8S_DIR="$PROJECT_ROOT/kubernetes/mern-app"

# Default options
BUILD=false
PUSH=false
APPLY=false
IMAGE_TAG="latest"
DOCKER_USERNAME="${DOCKER_USERNAME:-yourusername}"
DOCKER_REGISTRY="${DOCKER_REGISTRY:-docker.io}"

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
    head -18 "$0" | tail -13
    exit 0
}

#------------------------------------------------------------------------------
# Parse Arguments
#------------------------------------------------------------------------------

while [[ $# -gt 0 ]]; do
    case $1 in
        --build)
            BUILD=true
            shift
            ;;
        --push)
            PUSH=true
            shift
            ;;
        --apply)
            APPLY=true
            shift
            ;;
        --tag)
            IMAGE_TAG="$2"
            shift 2
            ;;
        --registry)
            DOCKER_REGISTRY="$2"
            shift 2
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
# Build Docker Images
#------------------------------------------------------------------------------

build_images() {
    log_info "Building Docker images..."
    
    if [ ! -d "$APP_DIR" ]; then
        log_error "Application directory not found: $APP_DIR"
        log_info "Expected todo-app directory at: $APP_DIR"
        exit 1
    fi
    
    cd "$APP_DIR"
    
    # Build backend
    log_info "Building backend image..."
    docker build -t "${DOCKER_USERNAME}/todo-backend:${IMAGE_TAG}" ./backend
    log_success "Backend image built: ${DOCKER_USERNAME}/todo-backend:${IMAGE_TAG}"
    
    # Build frontend
    log_info "Building frontend image..."
    docker build -t "${DOCKER_USERNAME}/todo-frontend:${IMAGE_TAG}" ./frontend
    log_success "Frontend image built: ${DOCKER_USERNAME}/todo-frontend:${IMAGE_TAG}"
    
    cd "$PROJECT_ROOT"
}

#------------------------------------------------------------------------------
# Push Docker Images
#------------------------------------------------------------------------------

push_images() {
    log_info "Pushing Docker images to registry..."
    
    # Check if logged in to Docker
    if ! docker info | grep -q "Username"; then
        log_warning "Not logged in to Docker. Running docker login..."
        docker login
    fi
    
    # Push backend
    log_info "Pushing backend image..."
    docker push "${DOCKER_USERNAME}/todo-backend:${IMAGE_TAG}"
    log_success "Backend image pushed"
    
    # Push frontend
    log_info "Pushing frontend image..."
    docker push "${DOCKER_USERNAME}/todo-frontend:${IMAGE_TAG}"
    log_success "Frontend image pushed"
}

#------------------------------------------------------------------------------
# Update Kubernetes Manifests
#------------------------------------------------------------------------------

update_manifests() {
    log_info "Updating Kubernetes manifests with image tag: ${IMAGE_TAG}..."
    
    # Update backend deployment
    sed -i "s|image: ${DOCKER_USERNAME}/todo-backend:.*|image: ${DOCKER_USERNAME}/todo-backend:${IMAGE_TAG}|g" \
        "$K8S_DIR/backend-deployment.yaml"
    log_success "Updated backend-deployment.yaml"
    
    # Update frontend deployment
    sed -i "s|image: ${DOCKER_USERNAME}/todo-frontend:.*|image: ${DOCKER_USERNAME}/todo-frontend:${IMAGE_TAG}|g" \
        "$K8S_DIR/frontend-deployment.yaml"
    log_success "Updated frontend-deployment.yaml"
}

#------------------------------------------------------------------------------
# Apply Kubernetes Manifests
#------------------------------------------------------------------------------

apply_manifests() {
    log_info "Applying Kubernetes manifests..."
    
    # Check if kubectl is configured
    if ! kubectl cluster-info &> /dev/null; then
        log_error "kubectl is not configured or cluster is not accessible"
        log_info "Configure kubectl to access your cluster first"
        exit 1
    fi
    
    # Apply namespace
    log_info "Applying namespace..."
    kubectl apply -f "$PROJECT_ROOT/kubernetes/namespaces/mern-app-namespace.yaml"
    
    # Apply manifests
    log_info "Applying MERN app manifests..."
    kubectl apply -f "$K8S_DIR/"
    
    # Wait for deployments
    log_info "Waiting for deployments to be ready..."
    kubectl rollout status deployment/backend -n mern-app --timeout=300s
    kubectl rollout status deployment/frontend -n mern-app --timeout=300s
    
    log_success "All deployments are ready"
    
    # Display pod status
    log_info "Pod status:"
    kubectl get pods -n mern-app -o wide
}

#------------------------------------------------------------------------------
# Verify Deployment
#------------------------------------------------------------------------------

verify_deployment() {
    log_info "Verifying deployment..."
    
    # Get ALB DNS from Terraform
    cd "$PROJECT_ROOT/terraform"
    if terraform output alb_dns_name &> /dev/null; then
        local alb_dns=$(terraform output -raw alb_dns_name)
        
        echo ""
        echo "=============================================================================="
        echo -e "${GREEN}Deployment Complete!${NC}"
        echo "=============================================================================="
        echo ""
        echo "Application URLs:"
        echo "  Frontend: http://${alb_dns}"
        echo "  Backend:  http://${alb_dns}/api"
        echo "  Health:   http://${alb_dns}/api/health"
        echo ""
        echo "To verify:"
        echo "  curl http://${alb_dns}/health"
        echo "  curl http://${alb_dns}/api/health"
        echo ""
    else
        log_warning "Could not retrieve ALB DNS. Check Terraform outputs."
    fi
    
    cd "$PROJECT_ROOT"
}

#------------------------------------------------------------------------------
# Main
#------------------------------------------------------------------------------

main() {
    echo ""
    echo "=============================================================================="
    echo -e "${BLUE}MERN Application Deployment${NC}"
    echo "=============================================================================="
    echo ""
    echo "Configuration:"
    echo "  Docker Username: ${DOCKER_USERNAME}"
    echo "  Image Tag:       ${IMAGE_TAG}"
    echo "  Build:           ${BUILD}"
    echo "  Push:            ${PUSH}"
    echo "  Apply:           ${APPLY}"
    echo ""
    
    if [ "$BUILD" = true ]; then
        build_images
    fi
    
    if [ "$PUSH" = true ]; then
        push_images
    fi
    
    # Always update manifests if building or pushing
    if [ "$BUILD" = true ] || [ "$PUSH" = true ]; then
        update_manifests
    fi
    
    if [ "$APPLY" = true ]; then
        apply_manifests
    fi
    
    if [ "$APPLY" = true ] || [ "$PUSH" = true ]; then
        verify_deployment
    fi
    
    if [ "$BUILD" = false ] && [ "$PUSH" = false ] && [ "$APPLY" = false ]; then
        log_warning "No action specified. Use --build, --push, or --apply flags."
        log_info "Run ./scripts/deploy.sh --help for usage information."
    fi
}

main
