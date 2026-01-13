#!/bin/bash
set -e
echo "Debug script starting..."

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config.sh"
source "$SCRIPT_DIR/helpers.sh"

echo "Helpers sourced."
echo "Master IP: $MASTER_IP"

if [ $# -gt 0 ]; then
    echo "Executing custom command: $*"
    ssh_exec "$MASTER_IP" "$*"
    exit 0
fi

echo "Testing normal connectivity..."
ssh_exec "$MASTER_IP" "hostname"
echo "Success (normal)."

echo "---------------------------------------------------"
echo "Testing SUDO connectivity..."
echo "If this hangs or fails, sudo requires a password."
echo "---------------------------------------------------"
ssh_exec "$MASTER_IP" "sudo -n id"
echo "Success (sudo)."
