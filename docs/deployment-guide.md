# MERN Infrastructure Deployment Guide

This guide provides step-by-step instructions for deploying the MERN Todo application infrastructure on AWS.

## Prerequisites

### Required Tools

| Tool | Version | Installation | Required For |
|------|---------|--------------|--------------|
| Terraform | >= 1.5.0 | [terraform.io](https://terraform.io) | Infrastructure provisioning |
| AWS CLI | >= 2.0 | [aws.amazon.com/cli](https://aws.amazon.com/cli/) | AWS authentication |
| SSH Client | Any | Built-in (Linux/Mac) or Git Bash (Windows) | Remote access |
| Ansible | >= 2.14 | `pip install ansible` | **Option A only** (Linux/WSL) |
| kubectl | >= 1.28 | [kubernetes.io](https://kubernetes.io/docs/tasks/tools/) | Cluster management |
| Docker | >= 24.0 | [docker.com](https://docker.com) | Building images |

### AWS Requirements
- AWS Account with appropriate permissions
- AWS CLI configured (`aws configure`)
- EC2 key pair created in target region
- (Optional) ACM certificate for HTTPS

---

## Deployment Options

You have **two options** for configuring the Kubernetes cluster after Terraform provisioning:

| Option | Best For | Requirements |
|--------|----------|--------------|
| **Option A: Ansible** | Linux/Mac or WSL users | Ansible installed |
| **Option B: Bash Scripts** | Windows users (no WSL) | Git Bash or similar |

Both options achieve the same end result. Choose based on your environment.

---

## Quick Start

### Option A: Using Ansible (Linux/Mac/WSL)

```bash
# 1. Clone the repository
git clone https://github.com/Saad-Muhammad/mern-infrastructure.git
cd mern-infrastructure

# 2. Configure Terraform variables
cp terraform/terraform.tfvars.example terraform/terraform.tfvars
# Edit terraform.tfvars with your values

# 3. Run the setup script
chmod +x scripts/setup.sh
./scripts/setup.sh
```

### Option B: Using Bash Scripts (Windows/Any)

```bash
# 1. Clone the repository
git clone https://github.com/Saad-Muhammad/mern-infrastructure.git
cd mern-infrastructure

# 2. Configure Terraform variables
cp terraform/terraform.tfvars.example terraform/terraform.tfvars
# Edit terraform.tfvars with your values

# 3. Run the setup script with bash option
chmod +x scripts/setup.sh
./scripts/setup.sh --use-bash
```

---

## Detailed Deployment Steps

### Step 1: Configure Terraform Variables

Edit `terraform/terraform.tfvars`:

```hcl
project_name = "mern-app"
environment  = "production"
aws_region   = "us-east-1"

# Replace with your IP (find with: curl ifconfig.me)
allowed_ssh_cidrs = ["YOUR_IP/32"]

# Your AWS key pair name
key_name = "your-key-pair-name"

# Optional: ACM certificate for HTTPS
acm_certificate_arn = ""
```

### Step 2: Provision Infrastructure with Terraform

```bash
cd terraform

# Initialize Terraform
terraform init

# Review the plan
terraform plan

# Apply (type 'yes' to confirm)
terraform apply

# Save outputs for later use
terraform output > ../outputs.txt
```

After Terraform completes, note down these important outputs:
- `bastion_public_ip` - For SSH access
- `master_private_ip` - K8s master node
- `worker_private_ips` - K8s worker nodes
- `mongodb_private_ip` - MongoDB server
- `alb_dns_name` - Application URL

---

## Step 3: Configure the Cluster

Choose **ONE** of the following options:

### Option A: Using Ansible (Linux/Mac/WSL)

#### A.1: Generate Ansible Inventory

```bash
# Get values from Terraform
cd terraform
BASTION_IP=$(terraform output -raw bastion_public_ip)
MASTER_IP=$(terraform output -raw master_private_ip)
WORKER_IPS=$(terraform output -json worker_private_ips)
MONGODB_IP=$(terraform output -raw mongodb_private_ip)

# Create inventory file
cd ../ansible
cp inventory/hosts.ini.example inventory/hosts.ini

# Update hosts.ini with actual IPs from above
# Also update the SSH key path in all.yml
```

#### A.2: Update Ansible Variables

Edit `ansible/inventory/group_vars/all.yml`:

```yaml
# Update these values
ansible_ssh_private_key_file: "~/.ssh/your-actual-key.pem"
mongodb_admin_password: "your-secure-admin-password"
mongodb_app_password: "your-secure-app-password"
grafana_admin_password: "your-secure-grafana-password"
```

#### A.3: Run Ansible Playbooks

```bash
cd ansible

# Run all playbooks in sequence
ansible-playbook -i inventory/hosts.ini playbooks/01-prerequisites.yml
ansible-playbook -i inventory/hosts.ini playbooks/02-init-cluster.yml
ansible-playbook -i inventory/hosts.ini playbooks/03-join-workers.yml
ansible-playbook -i inventory/hosts.ini playbooks/04-install-cni.yml
ansible-playbook -i inventory/hosts.ini playbooks/05-install-helm.yml
ansible-playbook -i inventory/hosts.ini playbooks/06-deploy-monitoring.yml
ansible-playbook -i inventory/hosts.ini playbooks/07-deploy-argocd.yml
ansible-playbook -i inventory/hosts.ini playbooks/08-setup-mongodb.yml
```

---

### Option B: Using Bash Scripts (Windows/Any)

This option is ideal for Windows users who don't have WSL, or anyone who prefers shell scripts.

#### B.1: Set Environment Variables

Get the IPs from Terraform and set them as environment variables:

```bash
# In Git Bash or similar terminal
cd terraform

# Export the required variables
export BASTION_IP=$(terraform output -raw bastion_public_ip)
export MASTER_IP=$(terraform output -raw master_private_ip)
export WORKER_IPS=$(terraform output -json worker_private_ips | jq -r '. | join(" ")')
export MONGODB_IP=$(terraform output -raw mongodb_private_ip)
export SSH_KEY_PATH="$HOME/.ssh/your-key.pem"

# Verify variables are set
echo "BASTION_IP: $BASTION_IP"
echo "MASTER_IP: $MASTER_IP"
echo "WORKER_IPS: $WORKER_IPS"
echo "MONGODB_IP: $MONGODB_IP"
echo "SSH_KEY_PATH: $SSH_KEY_PATH"
```

#### B.2: (Optional) Update Configuration

Edit `scripts/bash/config.sh` if you want to change default values:

```bash
# Kubernetes version
KUBERNETES_VERSION="1.29"

# MongoDB credentials
MONGODB_ADMIN_PASSWORD="your-secure-admin-password"
MONGODB_APP_PASSWORD="your-secure-app-password"

# Grafana password
GRAFANA_ADMIN_PASSWORD="your-secure-grafana-password"
```

#### B.3: Run All Bash Scripts

```bash
cd scripts/bash

# Make scripts executable
chmod +x *.sh

# Run the master orchestration script
./run-all.sh
```

This will execute all 8 scripts in sequence:
1. Install Docker, containerd, kubeadm on all nodes
2. Initialize Kubernetes cluster on master
3. Join worker nodes to cluster
4. Install Calico CNI
5. Install Helm
6. Deploy Prometheus + Grafana monitoring
7. Deploy ArgoCD
8. Setup MongoDB

#### B.4: Partial Runs (if needed)

```bash
# If a script fails, you can resume from that step:
./run-all.sh --from 4   # Resume from step 4

# Or run a single step:
./run-all.sh --only 6   # Only deploy monitoring

# Skip MongoDB if not needed:
./run-all.sh --skip-mongodb
```

---

## Step 4: Configure kubectl

After cluster configuration completes:

```bash
# SSH to master node via bastion
ssh -i ~/.ssh/your-key.pem -J ubuntu@<BASTION_IP> ubuntu@<MASTER_IP>

# On master node, get kubeconfig
cat ~/.kube/config

# Copy config to local machine and update server address if needed
```

## Step 5: Update Kubernetes Manifests

Update MongoDB IP in configmap:

```bash
cd kubernetes/mern-app

# Edit backend-configmap.yaml
# Replace <MONGODB_PRIVATE_IP> with actual IP

# Edit backend-secret.yaml
# Update MongoDB URI with actual credentials
echo -n 'mongodb://todo_user:YOUR_PASSWORD@MONGODB_IP:27017/todo_app' | base64
```

## Step 6: Deploy Application via ArgoCD

```bash
# Apply ArgoCD application
kubectl apply -f argocd/applications/mern-app.yaml

# Check ArgoCD status
kubectl get applications -n argocd

# Or access ArgoCD UI
# Get password: cat scripts/bash/argocd-credentials.txt (if using bash scripts)
# Or from master node: cat ~/argocd-credentials.txt
```

---

## Accessing the Application

| Service | URL |
|---------|-----|
| Frontend | http://\<ALB_DNS\> |
| Backend API | http://\<ALB_DNS\>/api |
| Grafana | http://\<ALB_DNS\>/grafana |
| ArgoCD | https://\<WORKER_IP\>:30080 |

Get the ALB DNS:
```bash
cd terraform
terraform output alb_dns_name
```

---

## Verification Checklist

- [ ] ALB health checks passing (AWS Console → EC2 → Target Groups)
- [ ] All Kubernetes nodes Ready: `kubectl get nodes`
- [ ] All pods Running: `kubectl get pods -n mern-app`
- [ ] Frontend loads in browser
- [ ] API responds: `curl http://<ALB>/api/health`
- [ ] Create/list todos works
- [ ] Grafana accessible and showing metrics
- [ ] ArgoCD synced and healthy

---

## Troubleshooting

### SSH Connection Issues

```bash
# Test bastion connection
ssh -i ~/.ssh/your-key.pem ubuntu@<BASTION_IP>

# Test jump to master
ssh -i ~/.ssh/your-key.pem -J ubuntu@<BASTION_IP> ubuntu@<MASTER_IP>

# Check key permissions (must be 600)
chmod 600 ~/.ssh/your-key.pem
```

### Bash Script Issues (Option B)

```bash
# Enable debug mode
bash -x scripts/bash/run-all.sh

# Check if environment variables are set
echo $BASTION_IP $MASTER_IP

# Resume from failed step
./run-all.sh --from <step_number>
```

### Kubernetes Issues

```bash
# Check node status
kubectl get nodes -o wide

# Check pod logs
kubectl logs -n mern-app deployment/backend

# Describe pod for events
kubectl describe pod -n mern-app <pod-name>
```

### MongoDB Connection

```bash
# SSH to MongoDB server
ssh -i ~/.ssh/your-key.pem -J ubuntu@<BASTION_IP> ubuntu@<MONGODB_IP>

# Test MongoDB
mongosh -u admin -p 'password' --authenticationDatabase admin
```

### ALB Health Check Failures

1. Verify pods are running
2. Check NodePort services: `kubectl get svc -n mern-app`
3. Test from worker node: `curl localhost:30001/health`
4. Check security group rules

---

## Reference: Script Files

### Bash Scripts (scripts/bash/)

| Script | Description |
|--------|-------------|
| `config.sh` | Configuration variables |
| `helpers.sh` | Utility functions |
| `01-prerequisites.sh` | Docker, containerd, kubeadm |
| `02-init-cluster.sh` | K8s master initialization |
| `03-join-workers.sh` | Worker node joining |
| `04-install-cni.sh` | Calico CNI |
| `05-install-helm.sh` | Helm package manager |
| `06-deploy-monitoring.sh` | Prometheus + Grafana |
| `07-deploy-argocd.sh` | ArgoCD GitOps |
| `08-setup-mongodb.sh` | MongoDB + Exporter |
| `run-all.sh` | Orchestration script |

### Ansible Playbooks (ansible/playbooks/)

Same functionality as bash scripts, requires Linux/WSL.

---

## Cleanup

To destroy all resources:

```bash
cd terraform
terraform destroy

# Type 'yes' to confirm
```

> ⚠️ **Warning**: This will delete all infrastructure including data!
