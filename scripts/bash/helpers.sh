#!/bin/bash
#==============================================================================
# Helper Functions for MERN Infrastructure Scripts
#==============================================================================
# Common utility functions for logging, SSH execution, and error handling.
#==============================================================================

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

#------------------------------------------------------------------------------
# Logging Functions
#------------------------------------------------------------------------------

log_info() {
    printf "${BLUE}[INFO]${NC} %s\n" "$1" >&2
}

log_success() {
    printf "${GREEN}[SUCCESS]${NC} %s\n" "$1" >&2
}

log_warning() {
    printf "${YELLOW}[WARNING]${NC} %s\n" "$1" >&2
}

log_error() {
    printf "${RED}[ERROR]${NC} %s\n" "$1" >&2
}

log_step() {
    printf "\n${CYAN}==>${NC} ${CYAN}%s${NC}\n" "$1" >&2
}

log_header() {
    echo "" >&2
    echo "==============================================================================" >&2
    printf "${BLUE}%s${NC}\n" "$1" >&2
    echo "==============================================================================" >&2
    echo "" >&2
}

#------------------------------------------------------------------------------
# SSH Execution Functions
#------------------------------------------------------------------------------

# Execute command on remote host via bastion
# Usage: ssh_exec <host_ip> <command>
ssh_exec() {
    local host_ip="$1"
    shift
    local command="$*"
    
    if [ -z "$BASTION_IP" ]; then
        log_error "BASTION_IP not set. Please configure it in config.sh or export it."
        return 1
    fi
    
    # Construct ProxyCommand with explicit key for bastion
    local proxy_cmd="ssh -i \"$SSH_KEY_PATH\" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -W %h:%p $SSH_USER@$BASTION_IP"
    
    log_info "DEBUG: Connecting to $host_ip via $BASTION_IP..."
    # set -x
    ssh -i "$SSH_KEY_PATH" \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        -o ConnectTimeout=10 \
        -o ProxyCommand="$proxy_cmd" \
        "$SSH_USER@$host_ip" \
        "$command"
    # set +x
}

# Execute command on remote host via bastion with sudo
# Usage: ssh_exec_sudo <host_ip> <command>
ssh_exec_sudo() {
    local host_ip="$1"
    shift
    local command="$*"
    
    ssh_exec "$host_ip" "sudo bash -c '$command'"
}

# Execute command directly on bastion host
# Usage: ssh_bastion <command>
ssh_bastion() {
    local command="$*"
    
    ssh -i "$SSH_KEY_PATH" \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        -o ConnectTimeout=10 \
        "$SSH_USER@$BASTION_IP" \
        "$command"
}

# Copy file to remote host via bastion
# Usage: scp_to_host <local_file> <host_ip> <remote_path>
scp_to_host() {
    local local_file="$1"
    local host_ip="$2"
    local remote_path="$3"
    
    local proxy_cmd="ssh -i \"$SSH_KEY_PATH\" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -W %h:%p $SSH_USER@$BASTION_IP"
    
    scp -i "$SSH_KEY_PATH" \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        -o ConnectTimeout=10 \
        -o ProxyCommand="$proxy_cmd" \
        "$local_file" \
        "$SSH_USER@$host_ip:$remote_path"
}

# Copy script content to remote host and execute
# Usage: remote_script <host_ip> <script_content>
remote_script() {
    local host_ip="$1"
    local script_content="$2"
    
    ssh_exec "$host_ip" "bash -s" <<< "$script_content"
}

# Copy script content to remote host and execute with sudo
# Usage: remote_script_sudo <host_ip> <script_content>
remote_script_sudo() {
    local host_ip="$1"
    local script_content="$2"
    
    ssh_exec "$host_ip" "sudo bash -s" <<< "$script_content"
}

#------------------------------------------------------------------------------
# Utility Functions
#------------------------------------------------------------------------------

# Wait for SSH to be available on a host
# Usage: wait_for_ssh <host_ip> [max_attempts]
wait_for_ssh() {
    local host_ip="$1"
    local max_attempts="${2:-30}"
    local attempt=1
    
    log_info "Waiting for SSH on $host_ip..."
    
    while [ $attempt -le $max_attempts ]; do
        if ssh_exec "$host_ip" "exit" 2>/dev/null; then
            log_success "SSH is available on $host_ip"
            return 0
        fi
        log_info "Attempt $attempt/$max_attempts - Waiting..."
        sleep 10
        attempt=$((attempt + 1))
    done
    
    log_error "Timeout waiting for SSH on $host_ip"
    return 1
}

# Check if a command exists on remote host
# Usage: remote_command_exists <host_ip> <command>
remote_command_exists() {
    local host_ip="$1"
    local command="$2"
    
    ssh_exec "$host_ip" "command -v $command" &>/dev/null
}

# Get remote host's private IP address
# Usage: get_remote_ip <host_ip>
get_remote_ip() {
    local host_ip="$1"
    ssh_exec "$host_ip" "hostname -I | awk '{print \$1}'"
}

#------------------------------------------------------------------------------
# Validation Functions
#------------------------------------------------------------------------------

# Check if required environment variables are set
check_required_vars() {
    local missing=()
    
    for var in "$@"; do
        if [ -z "${!var}" ]; then
            missing+=("$var")
        fi
    done
    
    if [ ${#missing[@]} -gt 0 ]; then
        log_error "Missing required variables: ${missing[*]}"
        return 1
    fi
    
    return 0
}

# Validate SSH key exists
validate_ssh_key() {
    if [ ! -f "$SSH_KEY_PATH" ]; then
        log_error "SSH key not found at: $SSH_KEY_PATH"
        log_info "Please set SSH_KEY_PATH to your actual key location"
        return 1
    fi
    log_success "SSH key found: $SSH_KEY_PATH"
    return 0
}

#------------------------------------------------------------------------------
# Progress Tracking
#------------------------------------------------------------------------------

# Display step progress
# Usage: step_progress <step_number> <total_steps> <description>
# Display step progress
# Usage: step_progress <step_number> <total_steps> <description>
step_progress() {
    local step="$1"
    local total="$2"
    local description="$3"
    
    echo "" >&2
    echo "[${step}/${total}] ${description}" >&2
    echo "------------------------------------------------------------------------------" >&2
}

# Display completion message
show_completion() {
    local component="$1"
    echo "" >&2
    echo "==============================================================================" >&2
    echo "$component Complete!" >&2
    echo "==============================================================================" >&2
    echo "" >&2
}
