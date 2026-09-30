# Jenkins Setup for GitOps Progressive Delivery Platform

This directory contains the Jenkins provisioning configuration. There are two approaches to running Jenkins:

## Option 1: Jenkins as a Kubernetes Pod (Recommended for Kind Cluster)

### Why this approach:
- Single environment for all services (Jenkins + cluster)
- Easy to set up with Helm
- No additional cloud resources needed
- Perfect for local development and demo

### Setup steps:

```bash
# Add Jenkins Helm repository
helm repo add jenkins https://charts.jenkins.io
helm repo update

# Create namespace
kubectl create namespace jenkins

# Install Jenkins
helm install jenkins jenkins/jenkins \
  --namespace jenkins \
  --set controller.serviceType=NodePort \
  --set controller.nodePort=32080 \
  --values setup/values.yaml
```

### Access:
- URL: `http://localhost:32080` (or via `kubectl port-forward`)
- Initial admin password: `kubectl -n jenkins exec deployment/jenkins -c jenkins -- cat /var/jenkins_home/secrets/initialAdminPassword`

### Configure Jenkins:
1. Install required plugins (Pipeline, Git, Docker Pipeline, etc.)
2. Configure agent nodes (Docker agents with Docker, kubectl access)
3. Add pipeline job pointing to this repository
4. Configure webhook (optional for demo)

## Option 2: Jenkins on AWS EC2 (Production-Grade)

This approach uses Terraform to provision Jenkins on an EC2 instance.

### Requirements:
- AWS CLI configured with appropriate credentials
- Terraform (v1.5+)
- SSH key pair for EC2 access

### Setup:
```bash
cd terraform/
terraform init
terraform plan  # Review resources
terraform apply  # Create infrastructure
```

### Post-creation:
The instance will run the bootstrap script to install Jenkins and configure the pipeline.

## Key Differences from GitHub Actions Approach

| Feature | GitHub Actions (Old) | Jenkins (New) |
|---------|---------------------|--------------|
| Config File | `.github/workflows/*.yml` | `Jenkinsfile` (declarative) |
| Trigger | `push` event | SCM polling / webhook |
| Agent | GitHub-hosted runner | Self-hosted agent (Docker or VM) |
| Secret Storage | GitHub Secrets | Jenkins Credential Store |
| Image Registry | `ghcr.io` (public) | Configurable (EC2/EKS registry) |
| Pipeline Visibility | GitHub UI only | Jenkins web dashboard + build artifacts |

## Pipeline Configuration

The `Jenkinsfile` defines the complete pipeline:

1. **Checkout** - Clone source code
2. **Lint** - Parallel Go and JavaScript linting
3. **Unit Tests** - Parallel test execution with coverage
4. **Build** - Docker multi-stage image builds
5. **Security** - Trivy vulnerability scanning (blocks on HIGH/CRITICAL)
6. **Push** - Registry push (requires credential setup)
7. **Update GitOps** - Modify gitops manifests
8. **Deploy** - Apply to Kubernetes cluster
9. **Chaos Test** - Regression test rollback behavior

## Security Best Practices

- Use Jenkins Credential Store for registry passwords
- Never store secrets in `Jenkinsfile` or repository
- Configure role-based access control (RBAC) for Jenkins
- Use agent isolation (separate agents per pipeline)
- Enable audit logging for all pipeline executions
- Configure webhook authentication (if using webhooks)

## Monitoring Pipeline Health

Jenkins provides:
- Build history and trends
- Test result tracking
- Coverage reports (archived as artifacts)
- Pipeline execution time metrics
- Email/Slack notifications (via plugins)
