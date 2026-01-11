# MERN Infrastructure Deployment Guide

This guide provides step-by-step instructions for deploying the MERN Todo application infrastructure on AWS.

## Prerequisites

### Required Tools
| Tool | Version | Installation |
|------|---------|--------------|
| Terraform | >= 1.5.0 | [terraform.io](https://terraform.io) |
| Ansible | >= 2.14 | `pip install ansible` |
| AWS CLI | >= 2.0 | [aws.amazon.com/cli](https://aws.amazon.com/cli/) |
| kubectl | >= 1.28 | [kubernetes.io](https://kubernetes.io/docs/tasks/tools/) |
| Docker | >= 24.0 | [docker.com](https://docker.com) |

### AWS Requirements
- AWS Account with appropriate permissions
- AWS CLI configured (`aws configure`)
- EC2 key pair created in target region
- (Optional) ACM certificate for HTTPS

## Quick Start

```bash
# 1. Clone the repository
git clone https://github.com/yourusername/mern-infrastructure.git
cd mern-infrastructure

# 2. Configure Terraform variables
cp terraform/terraform.tfvars.example terraform/terraform.tfvars
# Edit terraform.tfvars with your values

# 3. Run the setup script
chmod +x scripts/setup.sh
./scripts/setup.sh
```

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

### Step 3: Configure Ansible Inventory

Generate inventory from Terraform outputs:

```bash
# Get values from Terraform
BASTION_IP=$(terraform output -raw bastion_public_ip)
MASTER_IP=$(terraform output -raw master_private_ip)
WORKER_IPS=$(terraform output -json worker_private_ips)
MONGODB_IP=$(terraform output -raw mongodb_private_ip)

# Create inventory file
cd ../ansible
cp inventory/hosts.ini.example inventory/hosts.ini

# Update hosts.ini with actual IPs
# Also update the SSH key path
```

### Step 4: Update Ansible Variables

Edit `ansible/inventory/group_vars/all.yml`:

```yaml
# Update these values
ansible_ssh_private_key_file: "~/.ssh/your-actual-key.pem"
mongodb_admin_password: "your-secure-admin-password"
mongodb_app_password: "your-secure-app-password"
grafana_admin_password: "your-secure-grafana-password"
```

### Step 5: Run Ansible Playbooks

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

### Step 6: Configure kubectl

```bash
# SSH to master node via bastion
ssh -i ~/.ssh/your-key.pem -J ubuntu@<BASTION_IP> ubuntu@<MASTER_IP>

# On master node, get kubeconfig
cat ~/.kube/config

# Copy config to local machine and update server address if needed
```

### Step 7: Update Kubernetes Manifests

Update MongoDB IP in configmap:

```bash
cd kubernetes/mern-app

# Edit backend-configmap.yaml
# Replace <MONGODB_PRIVATE_IP> with actual IP

# Edit backend-secret.yaml
# Update MongoDB URI with actual credentials
echo -n 'mongodb://todo_user:YOUR_PASSWORD@MONGODB_IP:27017/todo_app' | base64
```

### Step 8: Deploy Application via ArgoCD

```bash
# Apply ArgoCD application
kubectl apply -f argocd/applications/mern-app.yaml

# Check ArgoCD status
kubectl get applications -n argocd

# Or access ArgoCD UI
# Get password from master node: ~/argocd-credentials.txt
```

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

## Verification Checklist

- [ ] ALB health checks passing (AWS Console → EC2 → Target Groups)
- [ ] All Kubernetes nodes Ready: `kubectl get nodes`
- [ ] All pods Running: `kubectl get pods -n mern-app`
- [ ] Frontend loads in browser
- [ ] API responds: `curl http://<ALB>/api/health`
- [ ] Create/list todos works
- [ ] Grafana accessible and showing metrics
- [ ] ArgoCD synced and healthy

## Troubleshooting

### SSH Connection Issues

```bash
# Test bastion connection
ssh -i ~/.ssh/your-key.pem ubuntu@<BASTION_IP>

# Test jump to master
ssh -i ~/.ssh/your-key.pem -J ubuntu@<BASTION_IP> ubuntu@<MASTER_IP>
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

## Cleanup

To destroy all resources:

```bash
cd terraform
terraform destroy

# Type 'yes' to confirm
```

> ⚠️ **Warning**: This will delete all infrastructure including data!
