# MERN Infrastructure Architecture

This document provides a detailed overview of the infrastructure architecture for the MERN Todo application deployed on AWS.

## Architecture Overview

```
                                    ┌─────────────────────────────────────────────────────────────────┐
                                    │                         AWS VPC (10.0.0.0/16)                    │
                                    │                                                                  │
                                    │  ┌──────────────────────────────────────────────────────────┐   │
    ┌──────────┐                    │  │              Public Subnets (10.0.1.0/24, 10.0.2.0/24)   │   │
    │          │                    │  │                                                          │   │
    │ Internet │◄───────────────────┼──┤  ┌─────────────┐     ┌─────────────┐     ┌──────────┐   │   │
    │          │        IGW         │  │  │     ALB     │     │ NAT Gateway │     │ Bastion  │   │   │
    └──────────┘                    │  │  │  (mern-app) │     │             │     │  Host    │   │   │
         │                          │  │  └──────┬──────┘     └──────┬──────┘     └────┬─────┘   │   │
         │                          │  │         │                   │                 │         │   │
         │                          │  └─────────┼───────────────────┼─────────────────┼─────────┘   │
         │                          │            │                   │                 │             │
         ▼                          │  ┌─────────┼───────────────────┼─────────────────┼─────────┐   │
    ┌──────────┐                    │  │         ▼                   │                 ▼         │   │
    │  ALB:80  │                    │  │  Private Subnets (10.0.10.0/24, 10.0.11.0/24)          │   │
    │  ALB:443 │                    │  │                                                         │   │
    └──────────┘                    │  │  ┌─────────────────────────────────────┐               │   │
         │                          │  │  │      Kubernetes Cluster (kubeadm)   │               │   │
         │                          │  │  │                                     │               │   │
         ├─── / ──────────────────► │  │  │  ┌──────────┐   ┌──────────────────┐│   ┌────────┐ │   │
         │    (30001)               │  │  │  │  Master  │   │  Worker Nodes    ││   │MongoDB │ │   │
         │                          │  │  │  │          │   │  ┌────────────┐  ││   │        │ │   │
         ├─── /api/* ────────────►  │  │  │  │ • API    │   │  │ Frontend   │  ││   │ • Data │ │   │
         │    (30002)               │  │  │  │ • etcd   │◄─►│  │ Backend    │  ││◄──│   EBS  │ │   │
         │                          │  │  │  │ • sched  │   │  │ Monitoring │  ││   │ • Auth │ │   │
         └─── /grafana/* ────────►  │  │  │  └──────────┘   │  │ ArgoCD     │  ││   │ • Logs │ │   │
              (30003)               │  │  │  t3.medium      │  └────────────┘  ││   └────────┘ │   │
                                    │  │  │                 │  2x t3.medium    ││   t3.large   │   │
                                    │  │  └─────────────────┴──────────────────┘│               │   │
                                    │  │                                         │               │   │
                                    │  └─────────────────────────────────────────────────────────┘   │
                                    │                                                                  │
                                    └─────────────────────────────────────────────────────────────────┘
```

## Network Architecture

### VPC Configuration
| Component | CIDR/Value |
|-----------|------------|
| VPC | 10.0.0.0/16 |
| Public Subnet 1 | 10.0.1.0/24 (AZ-a) |
| Public Subnet 2 | 10.0.2.0/24 (AZ-b) |
| Private Subnet 1 | 10.0.10.0/24 (AZ-a) |
| Private Subnet 2 | 10.0.11.0/24 (AZ-b) |
| Pod Network CIDR | 10.244.0.0/16 |
| Service CIDR | 10.96.0.0/12 |

### Traffic Flow

1. **Inbound Traffic (Internet → Application)**
   ```
   Internet → ALB (80/443) → Worker Nodes (NodePort) → Pods
   ```

2. **Path-Based Routing**
   | Path | Target Group | NodePort | Service |
   |------|-------------|----------|---------|
   | / (default) | Frontend | 30001 | frontend-service |
   | /api/* | Backend | 30002 | backend-service |
   | /grafana/* | Grafana | 30003 | grafana |

3. **Backend → MongoDB**
   ```
   Backend Pods → MongoDB EC2 (10.0.11.x:27017)
   ```

## Component Details

### Kubernetes Cluster
- **Version**: 1.29.x
- **CNI**: Calico v3.27
- **Container Runtime**: containerd

| Node | Instance Type | Role |
|------|--------------|------|
| k8s-master | t3.medium | Control plane |
| k8s-worker-1 | t3.medium | Workloads |
| k8s-worker-2 | t3.medium | Workloads |

### MongoDB Server
- **Version**: 7.0
- **Instance**: t3.large
- **Storage**: 100GB gp3 EBS (encrypted)
- **Authentication**: Enabled
- **Exporter**: Port 9216 for Prometheus

### Application Load Balancer
- **Type**: Application (Layer 7)
- **Health Checks**: HTTP on service health endpoints
- **Listeners**: HTTP (80), HTTPS (443 if configured)

## Security Architecture

### Security Groups

```
┌──────────────────────────────────────────────────────────────────┐
│                        Security Group Matrix                      │
├────────────────┬─────────────────────────────────────────────────┤
│ ALB SG         │ Ingress: 80,443 from 0.0.0.0/0                  │
│                │ Egress: 30000-32767 to Worker SG                │
├────────────────┼─────────────────────────────────────────────────┤
│ Bastion SG     │ Ingress: 22 from allowed IPs                    │
│                │ Egress: All                                      │
├────────────────┼─────────────────────────────────────────────────┤
│ Master SG      │ Ingress: 6443,2379-2380,10250-10252 from VPC    │
│                │ Ingress: 22 from Bastion SG                     │
│                │ Egress: All                                      │
├────────────────┼─────────────────────────────────────────────────┤
│ Worker SG      │ Ingress: 30000-32767 from ALB SG                │
│                │ Ingress: 10250 from Master SG                   │
│                │ Ingress: All from self (pod network)            │
│                │ Egress: All                                      │
├────────────────┼─────────────────────────────────────────────────┤
│ MongoDB SG     │ Ingress: 27017,9216 from Worker SG              │
│                │ Ingress: 22 from Bastion SG                     │
│                │ Egress: All                                      │
└────────────────┴─────────────────────────────────────────────────┘
```

## Monitoring Stack

### Prometheus
- **Metrics Collection**: Node, Pod, Container, Custom
- **Retention**: 15 days
- **Storage**: 50GB PVC

### Grafana
- **Access**: http://ALB/grafana
- **Dashboards**: Pre-configured for K8s and MongoDB
- **NodePort**: 30003

### MongoDB Exporter
- **Port**: 9216
- **Metrics**: Connection stats, operations, replication

## CI/CD Pipeline

```
┌─────────────┐     ┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│  Developer  │────►│  todo-app   │────►│  DockerHub  │────►│   ArgoCD    │
│  Commits    │     │  GitHub     │     │  Registry   │     │   Sync      │
└─────────────┘     │  Actions    │     └─────────────┘     └──────┬──────┘
                    └──────┬──────┘                                │
                           │                                       ▼
                           │     ┌─────────────────┐     ┌─────────────────┐
                           └────►│    mern-        │────►│   Kubernetes    │
                                 │ infrastructure  │     │     Cluster     │
                                 │   (manifests)   │     └─────────────────┘
                                 └─────────────────┘
```

## Scaling Considerations

### Horizontal Scaling
- **Workers**: Add more worker nodes via Terraform
- **Pods**: Configure HPA for frontend/backend deployments
- **MongoDB**: Consider replica set for HA

### Vertical Scaling
- Upgrade instance types in Terraform variables
- Adjust resource requests/limits in deployments

## Backup Strategy

### MongoDB
- EBS snapshots (daily)
- mongodump to S3 (recommended)

### Kubernetes
- etcd backup on master node
- PVC snapshots for stateful data

### Infrastructure
- Terraform state in S3 with versioning
- Code in Git (version controlled)
