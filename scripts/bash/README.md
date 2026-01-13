# Bash Scripts for MERN Infrastructure

This directory contains bash script alternatives to the Ansible playbooks. Use these scripts if you prefer running from Windows without WSL or want a simpler automation approach.

## Prerequisites

- SSH access to your infrastructure (via bastion host)
- SSH key configured
- Terraform outputs available (or manual IP configuration)
- bash/Git Bash on Windows, or native bash on Linux/Mac

## Quick Start

### Option 1: Using the Main Setup Script

```bash
# Run with bash scripts instead of Ansible
./scripts/setup.sh --use-bash

# Or run bash scripts only (assuming infrastructure is already provisioned)
./scripts/setup.sh --bash-only
```

### Option 2: Running Scripts Directly

1. **Set environment variables:**

```bash
export BASTION_IP="<your-bastion-public-ip>"
export MASTER_IP="<your-master-private-ip>"
export WORKER_IPS="<worker1-ip> <worker2-ip>"
export MONGODB_IP="<mongodb-private-ip>"
export SSH_KEY_PATH="$HOME/.ssh/your-key.pem"
```

2. **Run all scripts:**

```bash
cd scripts/bash
./run-all.sh
```

3. **Or run individual scripts:**

```bash
./01-prerequisites.sh
./02-init-cluster.sh
./03-join-workers.sh
./04-install-cni.sh
./05-install-helm.sh
./06-deploy-monitoring.sh
./07-deploy-argocd.sh
./08-setup-mongodb.sh
```

## Scripts Overview

| Script | Description | Ansible Equivalent |
|--------|-------------|-------------------|
| `config.sh` | Configuration variables | `group_vars/all.yml` |
| `helpers.sh` | Utility functions (SSH, logging) | - |
| `01-prerequisites.sh` | Docker, containerd, kubeadm | `01-prerequisites.yml` + roles |
| `02-init-cluster.sh` | Initialize K8s master | `02-init-cluster.yml` |
| `03-join-workers.sh` | Join worker nodes | `03-join-workers.yml` |
| `04-install-cni.sh` | Install Calico CNI | `04-install-cni.yml` |
| `05-install-helm.sh` | Install Helm | `05-install-helm.yml` |
| `06-deploy-monitoring.sh` | Prometheus + Grafana | `06-deploy-monitoring.yml` |
| `07-deploy-argocd.sh` | ArgoCD GitOps | `07-deploy-argocd.yml` |
| `08-setup-mongodb.sh` | MongoDB + Exporter | `08-setup-mongodb.yml` |
| `run-all.sh` | Orchestrator script | - |

## Advanced Usage

### Run from a Specific Step

```bash
# Start from step 4 (skip prerequisites and cluster init)
./run-all.sh --from 4
```

### Run Only One Step

```bash
# Only deploy monitoring
./run-all.sh --only 6
```

### Skip MongoDB Setup

```bash
./run-all.sh --skip-mongodb
```

### Dry Run

```bash
./run-all.sh --dry-run
```

## Configuration

Edit `config.sh` to customize:

- Kubernetes version
- MongoDB credentials
- Grafana password
- NodePort assignments
- Helm repository URLs

## Outputs

After successful execution:

- `join_command.sh` - Kubernetes join command for additional workers
- `argocd-credentials.txt` - ArgoCD admin password

## Troubleshooting

### SSH Connection Issues

1. Verify bastion is reachable: `ssh -i $SSH_KEY_PATH ubuntu@$BASTION_IP`
2. Check SSH key permissions: `chmod 600 $SSH_KEY_PATH`
3. Verify security groups allow SSH (port 22)

### Script Failures

Scripts are idempotent - you can safely re-run them. Use `--from` to resume from the failed step.

### View Logs

Add `-x` for debug output:
```bash
bash -x ./run-all.sh
```
