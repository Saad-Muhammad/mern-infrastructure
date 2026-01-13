#!/bin/bash
#==============================================================================
# Script 01: Prerequisites
#==============================================================================
# Installs Docker, containerd, and Kubernetes tools on all cluster nodes.
# Also configures kernel settings required by Kubernetes.
#
# Usage: ./01-prerequisites.sh
# 
# Mirrors: ansible/playbooks/01-prerequisites.yml
#          ansible/roles/docker/tasks/main.yml
#          ansible/roles/kubeadm/tasks/main.yml
#==============================================================================

set -e

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source configuration and helpers
source "$SCRIPT_DIR/config.sh"
source "$SCRIPT_DIR/helpers.sh"

#------------------------------------------------------------------------------
# Script to run on each K8s node (Docker + containerd installation)
#------------------------------------------------------------------------------
DOCKER_INSTALL_SCRIPT='
#!/bin/bash
set -e

echo "==> Installing Docker and containerd prerequisites..."

# Update apt cache
apt-get update

# Install required packages
apt-get install -y \
    apt-transport-https \
    ca-certificates \
    curl \
    gnupg \
    lsb-release \
    software-properties-common

# Create keyrings directory
mkdir -p /etc/apt/keyrings

# Add Docker GPG key
curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
chmod 644 /etc/apt/keyrings/docker.asc

# Add Docker repository
UBUNTU_CODENAME=$(lsb_release -cs)
echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu ${UBUNTU_CODENAME} stable" > /etc/apt/sources.list.d/docker.list

# Update apt cache with new repository
apt-get update

# Install Docker packages
apt-get install -y \
    docker-ce \
    docker-ce-cli \
    containerd.io \
    docker-buildx-plugin \
    docker-compose-plugin

echo "==> Configuring containerd..."

# Create containerd config directory
mkdir -p /etc/containerd

# Generate default containerd config
containerd config default > /etc/containerd/config.toml

# Configure containerd to use systemd cgroup driver
sed -i "s/SystemdCgroup = false/SystemdCgroup = true/g" /etc/containerd/config.toml

# Restart containerd
systemctl daemon-reload
systemctl restart containerd
systemctl enable containerd

# Start and enable Docker
systemctl start docker
systemctl enable docker

# Add ubuntu user to docker group
usermod -aG docker ubuntu

echo "==> Docker and containerd installation complete!"
'

#------------------------------------------------------------------------------
# Script to run on each K8s node (Kubeadm installation)
#------------------------------------------------------------------------------
generate_kubeadm_script() {
    local k8s_version="$1"
    cat << EOF
#!/bin/bash
set -e

echo "==> Installing Kubernetes components..."

# Disable swap
swapoff -a
sed -i '/swap/d' /etc/fstab

echo "==> Loading required kernel modules..."

# Load required kernel modules
modprobe overlay
modprobe br_netfilter

# Persist kernel modules
cat > /etc/modules-load.d/k8s.conf << MODULES
overlay
br_netfilter
MODULES

echo "==> Configuring sysctl for Kubernetes..."

# Configure sysctl for Kubernetes
cat > /etc/sysctl.d/k8s.conf << SYSCTL
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward = 1
SYSCTL

# Apply sysctl settings
sysctl --system

echo "==> Adding Kubernetes repository..."

# Create keyrings directory
mkdir -p /etc/apt/keyrings

# Add Kubernetes GPG key
curl -fsSL "https://pkgs.k8s.io/core:/stable:/v${k8s_version}/deb/Release.key" -o /etc/apt/keyrings/kubernetes-apt-keyring.asc
chmod 644 /etc/apt/keyrings/kubernetes-apt-keyring.asc

# Add Kubernetes repository
echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.asc] https://pkgs.k8s.io/core:/stable:/v${k8s_version}/deb/ /" > /etc/apt/sources.list.d/kubernetes.list

# Update apt cache
apt-get update

echo "==> Installing kubeadm, kubelet, kubectl..."

# Install Kubernetes packages
apt-get install -y kubelet kubeadm kubectl

# Hold Kubernetes packages at current version
apt-mark hold kubelet kubeadm kubectl

# Enable and start kubelet
systemctl daemon-reload
systemctl enable kubelet
systemctl start kubelet

echo "==> Kubernetes components installation complete!"

# Verify installations
echo ""
echo "Installed versions:"
echo "  Docker: \$(docker --version)"
echo "  Containerd: \$(containerd --version)"
echo "  Kubeadm: \$(kubeadm version -o short)"
echo "  Kubelet: \$(kubelet --version)"
echo "  Kubectl: \$(kubectl version --client -o yaml | grep gitVersion | awk '{print \$2}')"
EOF
}

#------------------------------------------------------------------------------
# Script for MongoDB server prerequisites
#------------------------------------------------------------------------------
MONGODB_PREREQ_SCRIPT='
#!/bin/bash
set -e

echo "==> Installing MongoDB server prerequisites..."

# Update apt cache
apt-get update

# Install common packages
apt-get install -y \
    apt-transport-https \
    ca-certificates \
    curl \
    gnupg \
    lsb-release \
    software-properties-common \
    python3-pip

# Try to install python3-pymongo (may not be available on all distros)
apt-get install -y python3-pymongo || pip3 install pymongo

echo "==> MongoDB server prerequisites installed!"
'

#------------------------------------------------------------------------------
# Main Execution
#------------------------------------------------------------------------------

main() {
    log_header "Installing Prerequisites on All Nodes"
    
    # Validate required variables
    check_required_vars BASTION_IP MASTER_IP || exit 1
    validate_ssh_key || exit 1
    
    # Convert worker IPs string to array
    IFS=' ' read -ra WORKER_ARRAY <<< "$WORKER_IPS"
    
    # Calculate total nodes
    local total_k8s_nodes=$((1 + ${#WORKER_ARRAY[@]}))
    local has_mongodb=0
    [ -n "$MONGODB_IP" ] && has_mongodb=1
    local total_steps=$((total_k8s_nodes * 2 + has_mongodb))
    local current_step=0
    
    #--------------------------------------------------------------------------
    # Install on Master Node
    #--------------------------------------------------------------------------
    echo "DEBUG: Starting Master Node installation..."
    current_step=$((current_step + 1))
    step_progress "$current_step" "$total_steps" "Installing Docker/containerd on Master ($MASTER_IP)"
    remote_script_sudo "$MASTER_IP" "$DOCKER_INSTALL_SCRIPT"
    log_success "Docker/containerd installed on master"
    
    current_step=$((current_step + 1))
    step_progress "$current_step" "$total_steps" "Installing Kubernetes components on Master ($MASTER_IP)"
    KUBEADM_SCRIPT=$(generate_kubeadm_script "$KUBERNETES_VERSION")
    remote_script_sudo "$MASTER_IP" "$KUBEADM_SCRIPT"
    log_success "Kubernetes components installed on master"
    
    #--------------------------------------------------------------------------
    # Install on Worker Nodes
    #--------------------------------------------------------------------------
    local worker_num=1
    for worker_ip in "${WORKER_ARRAY[@]}"; do
        current_step=$((current_step + 1))
        step_progress "$current_step" "$total_steps" "Installing Docker/containerd on Worker $worker_num ($worker_ip)"
        remote_script_sudo "$worker_ip" "$DOCKER_INSTALL_SCRIPT"
        log_success "Docker/containerd installed on worker $worker_num"
        
        current_step=$((current_step + 1))
        step_progress "$current_step" "$total_steps" "Installing Kubernetes components on Worker $worker_num ($worker_ip)"
        KUBEADM_SCRIPT=$(generate_kubeadm_script "$KUBERNETES_VERSION")
        remote_script_sudo "$worker_ip" "$KUBEADM_SCRIPT"
        log_success "Kubernetes components installed on worker $worker_num"
        
        worker_num=$((worker_num + 1))
    done
    
    #--------------------------------------------------------------------------
    # Install on MongoDB Server (if configured)
    #--------------------------------------------------------------------------
    if [ -n "$MONGODB_IP" ]; then
        current_step=$((current_step + 1))
        step_progress "$current_step" "$total_steps" "Installing prerequisites on MongoDB server ($MONGODB_IP)"
        remote_script_sudo "$MONGODB_IP" "$MONGODB_PREREQ_SCRIPT"
        log_success "Prerequisites installed on MongoDB server"
    fi
    
    show_completion "Prerequisites Installation"
    
    log_info "All nodes have Docker, containerd, and Kubernetes components installed."
    log_info "Next step: Run 02-init-cluster.sh to initialize the Kubernetes cluster."
}

main "$@"
