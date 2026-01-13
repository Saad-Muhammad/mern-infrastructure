# MERN Infrastructure on AWS

Production-ready infrastructure deployment for a 3-tier MERN stack application on AWS using Terraform, Ansible, and Kubernetes (kubeadm).

## Architecture

```
AWS VPC (10.0.0.0/16)
├── Public Subnets (10.0.1.0/24, 10.0.2.0/24)
│   ├── Application Load Balancer
│   ├── NAT Gateway
│   └── Bastion Host
│
└── Private Subnets (10.0.10.0/24, 10.0.11.0/24)
    ├── Kubernetes Cluster (kubeadm)
    │   ├── Master Node (t3.medium)
    │   └── Worker Nodes (2x t3.medium)
    └── MongoDB Instance (t3.large)
```

## Components

| Component | Technology |
|-----------|------------|
| Infrastructure | Terraform |
| Configuration | Ansible **or** Bash Scripts |
| Container Orchestration | Kubernetes (kubeadm) |
| Container Registry | DockerHub |
| Load Balancer | AWS ALB |
| Monitoring | Prometheus + Grafana |
| GitOps | ArgoCD |
| CI/CD | GitHub Actions |

## Quick Start

### Option A: Using Ansible (Linux/Mac/WSL)

```bash
# 1. Clone and configure
git clone <repo-url>
cd mern-infrastructure
cp terraform/terraform.tfvars.example terraform/terraform.tfvars
# Edit terraform.tfvars with your values

# 2. Run setup script
chmod +x scripts/setup.sh
./scripts/setup.sh
```

### Option B: Using Bash Scripts (Windows/Any)

```bash
# 1. Clone and configure
git clone <repo-url>
cd mern-infrastructure
cp terraform/terraform.tfvars.example terraform/terraform.tfvars
# Edit terraform.tfvars with your values

# 2. Run setup script with bash option
chmod +x scripts/setup.sh
./scripts/setup.sh --use-bash
```

## Project Structure

```
mern-infrastructure/
├── terraform/          # Infrastructure as Code
│   ├── modules/        # Reusable modules (vpc, ec2, alb, security-groups)
│   └── *.tf           # Root configuration
├── ansible/            # Configuration Management (Option A)
│   ├── playbooks/      # 8 playbooks for complete setup
│   ├── roles/          # Reusable roles (docker, kubeadm, monitoring)
│   └── inventory/      # Host definitions
├── kubernetes/         # K8s Manifests
│   ├── mern-app/       # Application deployments
│   ├── monitoring/     # Prometheus ServiceMonitor
│   └── namespaces/     # Namespace definitions
├── argocd/             # GitOps configuration
├── .github/workflows/  # CI/CD pipelines
├── scripts/
│   ├── setup.sh        # Main setup script
│   ├── deploy.sh       # Application deployment
│   └── bash/           # Bash scripts alternative (Option B)
└── docs/               # Documentation
```

## Traffic Flow

```
Internet → ALB:80 → Worker Nodes (NodePort) → Pods
│
├── /           → 30001 → Frontend
├── /api/*      → 30002 → Backend
└── /grafana/*  → 30003 → Grafana
```

## Prerequisites

- Terraform >= 1.5
- AWS CLI configured
- SSH client (Git Bash on Windows)
- Docker
- kubectl
- **For Ansible option**: Ansible >= 2.14 (Linux/WSL)

## Deployment Options

| Option | Command | Best For |
|--------|---------|----------|
| Ansible | `./scripts/setup.sh` | Linux/Mac/WSL users |
| Bash Scripts | `./scripts/setup.sh --use-bash` | Windows users |

## Deployment Steps

1. **Configure Variables**: Edit `terraform/terraform.tfvars`
2. **Terraform**: Provision AWS infrastructure
3. **Configure Cluster**: Ansible or Bash scripts
4. **ArgoCD**: Deploy application via GitOps

See [Deployment Guide](docs/deployment-guide.md) for detailed instructions.

## Access Information

| Service | URL |
|---------|-----|
| Application | http://\<ALB_DNS\> |
| API | http://\<ALB_DNS\>/api |
| Grafana | http://\<ALB_DNS\>/grafana |

## CI/CD Workflow

```
todo-app repo → GitHub Actions → DockerHub
                     ↓
         Update mern-infrastructure manifests
                     ↓
              ArgoCD auto-sync
                     ↓
           Deploy to Kubernetes
```

## Documentation

- [Architecture Overview](docs/architecture.md)
- [Deployment Guide](docs/deployment-guide.md)

## Security

- All EC2 instances in private subnets (except bastion)
- MongoDB with authentication enabled
- Encrypted EBS volumes
- Security groups with minimal access
- No hardcoded credentials (use secrets)

## Monitoring

- **Prometheus**: Metrics collection (15-day retention)
- **Grafana**: Dashboards and visualization
- **MongoDB Exporter**: Database metrics

## License

MIT
