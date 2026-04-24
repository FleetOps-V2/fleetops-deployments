# FleetOps Deployments

Dedicated deployment repository for FleetOps runtime assets.

This repo is intentionally separate from application repos (`fleetops-frontend`, `fleetops-auth-service`, `fleetops-vehicle-service`, `fleetops-request-service`, `fleetops-maintenance-service`) so deployment changes can be versioned, reviewed, and promoted independently.

## Why Separate Deployment Repo

- decouples app code lifecycle from infra/deployment lifecycle
- enables controlled environment promotion (dev -> prod)
- prepares for GitOps workflows (ArgoCD) and chart-driven releases (Helm)
- keeps security/network/policy assets centralized

## Current Infrastructure

- **HAProxy + SonarQube**: External instance with Elastic IP (public entry point)
- **Kubernetes Cluster**:
  - `master`: control-plane only
  - `worker-1`: workloads
  - `worker-2`: workloads + NFS server (private IP: `172.31.42.43`)
- **Dynamic Storage**: 
  - `nfs-subdir-external-provisioner` already implemented
  - StorageClass: `fleetops-nfs`

### Namespaces

- `fleetops-platform`: shared platform components (gateway, ingress, observability)
- `fleetops-dev`: development deployments and integration testing
- `fleetops-prod`: production deployments and promotion targets

## Namespace Strategy

- `fleetops-platform`: shared platform components (gateway, ingress, observability, shared ops tooling later)
- `fleetops-dev`: development deployments and integration testing
- `fleetops-prod`: production deployments and promotion targets

Dev and prod are separated to isolate risk, credentials, rollout timing, and policy enforcement.

## Repository Layout (Updated)

```text
fleetops-deployments/
  README.md
  k8s/
    base/
      storage/
        storageclass-nfs.yaml
    platform/
      namespace.yaml
      gateway.yaml
    dev/
      namespace.yaml
      database/
        postgres-configmap.yaml
        postgres-secret.yaml
        postgres-service.yaml
        postgres-statefulset.yaml
        fleetops-app-secret.yaml
        redis-deployment.yaml
        redis-service.yaml
      apps/
        dev-routes.yaml
        auth-service/
        frontend/
        maintenance-service/
        request-service/
        vehicle-service/
    prod/
      namespace.yaml
      database/
        postgres-configmap.yaml
        postgres-secret.yaml
        postgres-service.yaml
        postgres-statefulset.yaml
        fleetops-app-secret.yaml
        redis-deployment.yaml
        redis-service.yaml
      apps/
        prod-routes.yaml
        auth-service/
        frontend/
        maintenance-service/
        request-service/
        vehicle-service/
    policies/
      .gitkeep
  helm/
    .gitkeep
  argocd/
    .gitkeep
```

## Folder Purpose

- `k8s/base/storage`: shared storage primitives (StorageClass, PV/PVC patterns)
- `k8s/platform`: platform namespace-level resources
- `k8s/dev/database`: development database stack and configuration
- `k8s/prod/database`: production database stack and configuration
- `k8s/*/apps`: reserved for app workloads in next phase
- `k8s/policies`: reserved for network/security policies
- `helm`: reserved for future chart packaging
- `argocd`: reserved for future GitOps application definitions

## Current Phase Scope

Included in refined Phase 1:

- namespace manifests
- PostgreSQL storage foundation
- PostgreSQL StatefulSet/Service per environment
- ConfigMap and Secret templates

Not included yet:

- app Deployments/Services
- kgateway/ingress routes
- network policies
- Helm chart definitions
- ArgoCD application resources

## Apply Order

### Step-by-Step Commands

```bash
# 1. Create Namespaces
kubectl apply -f k8s/platform/namespace.yaml
kubectl apply -f k8s/dev/namespace.yaml
kubectl apply -f k8s/prod/namespace.yaml

# 2. Setup Storage (Dynamic Provisioning)
kubectl apply -f k8s/base/storage/storageclass-nfs.yaml

# 3. Deploy Database Configuration (Secrets & ConfigMaps)
kubectl apply -f k8s/dev/database/
kubectl apply -f k8s/prod/database/

# 4. Start Database Services
kubectl apply -f k8s/dev/database/postgres-service.yaml
kubectl apply -f k8s/prod/database/postgres-service.yaml

# 5. Deploy Platform Gateway
kubectl apply -f k8s/platform/gateway.yaml

# 6. Deploy Applications (Start with Dev for Testing)
kubectl apply -f k8s/dev/apps/
# For production:
kubectl apply -f k8s/prod/apps/
```

### File-by-File Breakdown

1. **Namespaces**
   - `k8s/platform/namespace.yaml`
   - `k8s/dev/namespace.yaml`
   - `k8s/prod/namespace.yaml`

2. **Storage Configuration**
   - `k8s/base/storage/storageclass-nfs.yaml`

3. **Database Configuration**
   - `k8s/dev/database/postgres-secret.yaml`
   - `k8s/dev/database/fleetops-app-secret.yaml`
   - `k8s/dev/database/postgres-configmap.yaml`
   - `k8s/prod/database/postgres-secret.yaml`
   - `k8s/prod/database/fleetops-app-secret.yaml`
   - `k8s/prod/database/postgres-configmap.yaml`

4. **Database Runtime**
   - `k8s/dev/database/postgres-service.yaml`
   - `k8s/dev/database/postgres-statefulset.yaml`
   - `k8s/prod/database/postgres-service.yaml`
   - `k8s/prod/database/postgres-statefulset.yaml`

5. **Platform Gateway**
   - `k8s/platform/gateway.yaml`

6. **Application Deployments**
   - `k8s/dev/apps/` (all services and routes)
   - `k8s/prod/apps/` (all services and routes)

## Manual Values Required

### Infrastructure
- **Elastic IP**: Replace `YOUR_EIP` in route files with actual HAProxy Elastic IP
- **NFS Server**: Already configured at `172.31.42.43` with dynamic provisioning

### Secrets (Replace Before Production)
- **JWT Secrets**: 
  - `k8s/dev/database/fleetops-app-secret.yaml` - JWT_SECRET key
  - `k8s/prod/database/fleetops-app-secret.yaml` - JWT_SECRET key
- **PostgreSQL Credentials**:
  - Currently using template passwords (base64 encoded)
  - Replace with secure production passwords

### Image Tags
- All deployments reference `johann2003/fleetops-*:latest`
- Update to CI-produced tags for production deployments

### Storage
- **Dev PostgreSQL**: 5Gi (dynamic provisioning)
- **Prod PostgreSQL**: 10Gi (dynamic provisioning)
- StorageClass: `fleetops-nfs` (already configured)

## Roadmap

- Phase 2: app Deployments, Services, probes
- Phase 3: kgateway routing (Completed)
- Phase 4: NetworkPolicies
- Phase 5: Helm + ArgoCD GitOps

## Phase 3 Deployment (kgateway Ingress)

To deploy the gateway and routing configuration:

### 1. Install kgateway
Install the standard Gateway API CRDs and kgateway:

```bash
kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.0.0/standard-install.yaml

helm repo add kgateway https://kgateway.dev/charts
helm repo update
helm install kgateway kgateway/kgateway \
  --namespace kgateway-system \
  --create-namespace
```

### 2. Apply Platform Resources
```bash
kubectl apply -f k8s/platform/namespace.yaml
kubectl apply -f k8s/platform/gateway.yaml
```

### 3. Deploy Environments (Example: Dev)
```bash
kubectl apply -f k8s/dev/namespace.yaml
kubectl apply -f k8s/dev/database/
kubectl apply -f k8s/dev/apps/
```

Access via: `http://dev.98.86.98.79.nip.io`
