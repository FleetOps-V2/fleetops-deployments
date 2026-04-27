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
- `monitoring`: Prometheus and Grafana observability stack

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
        storageclass-nfs.yaml          # NFS StorageClass (manual apply)
    platform/
      namespace.yaml                   # fleetops-platform namespace (manual apply)
      gateway.yaml                     # GatewayClass + Gateway (manual apply)
      gateway-proxy.yaml               # Nginx proxy Deployment + Service (manual apply)
      argocd-route.yaml                # ArgoCD HTTPRoute in argocd namespace (manual apply)
    dev/
      namespace.yaml
      database/  ...                   # Postgres + Redis stack (manual apply)
      apps/
        dev-routes.yaml                # Legacy raw HTTPRoute (NOT managed by ArgoCD)
        auth-service/ vehicle-service/ ...
    prod/
      namespace.yaml
      database/  ...                   # Postgres + Redis stack (manual apply)
      apps/
        prod-routes.yaml               # Legacy raw HTTPRoute (NOT managed by ArgoCD)
    policies/
      networkpolicies/
        platform/
          allow-proxy-to-gateway.yaml  # Gateway egress rules (manual apply)
          allow-public-to-gateway-proxy.yaml
          allow-to-monitoring.yaml
        monitoring/
          allow-from-gateway.yaml      # Grafana ingress + egress (manual apply)
          reference-grant.yaml         # CrossNamespace trust for Grafana (manual apply)
        argocd/
          allow-from-gateway.yaml      # ArgoCD-server ingress (manual apply)
        dev/
          allow-service-discovery.yaml
        prod/
          allow-service-discovery.yaml
  charts/                              # ALL Helm charts here are managed by ArgoCD
    routes/                            # Gateway HTTPRoutes chart (ArgoCD managed)
    auth-service/ vehicle-service/ ...
  argocd/
    root-app-dev.yaml                  # Bootstrap: apply once manually
    root-app-prod.yaml                 # Bootstrap: apply once manually
    apps/dev/  apps/prod/              # Child ArgoCD Applications (auto-discovered)
```

## Folder Purpose

- `k8s/base/storage`: shared storage primitives (StorageClass, PV/PVC patterns)
- `k8s/platform`: platform namespace-level resources (gateway, proxy)
- `k8s/dev/database`: development database stack and configuration
- `k8s/prod/database`: production database stack and configuration
- `k8s/*/apps`: reserved for app workloads in next phase
- `k8s/policies/networkpolicies`: network security policies for namespace isolation and traffic control
- `helm`: reserved for future chart packaging
- `argocd`: reserved for future GitOps application definitions

## Current Scope

Included:

- namespace manifests
- PostgreSQL storage foundation
- PostgreSQL StatefulSet/Service per environment
- ConfigMap and Secret templates
- Application Deployments, Services, and probes
- kgateway routing configuration
- Network policies for namespace isolation
- Prometheus and Grafana monitoring stack

Not included yet:

- Helm chart definitions
- ArgoCD application resources

## Apply Order (Full Recovery Runbook)

> [!IMPORTANT]
> **ArgoCD only watches `charts/` (Helm) and `argocd/apps/` directories.**
> Everything under `k8s/` must be applied manually — either on fresh cluster setup or after a full cluster restart.

### What ArgoCD Manages (Automatic)

| ArgoCD Application | Source Path | Namespace |
|---|---|---|
| `fleetops-platform-dev` | `charts/platform` | `fleetops-platform` |
| `fleetops-auth-dev` | `charts/auth-service` | `fleetops-dev` |
| `fleetops-vehicle-dev` | `charts/vehicle-service` | `fleetops-dev` |
| `fleetops-maintenance-dev` | `charts/maintenance-service` | `fleetops-dev` |
| `fleetops-request-dev` | `charts/request-service` | `fleetops-dev` |
| `fleetops-frontend-dev` | `charts/frontend` | `fleetops-dev` |
| `fleetops-routes-dev` | `charts/routes` | `fleetops-dev` |
| `fleetops-postgres-dev` | `charts/postgres` | `fleetops-dev` |
| `fleetops-redis-dev` | `charts/redis` | `fleetops-dev` |
| *(+ prod equivalents)* | `charts/*` | `fleetops-prod` |

### What You Must Apply Manually

These files live under `k8s/` and are **never touched by ArgoCD**.

---

#### Step 1 — Cluster Prerequisites (install once, never changes)

```bash
# Gateway API CRDs
kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.4.0/standard-install.yaml

# kgateway (Envoy-based Gateway controller)
helm install kgateway-crds oci://cr.kgateway.dev/kgateway-dev/charts/kgateway-crds \
  --namespace kgateway-system --create-namespace --version v2.2.1
helm install kgateway oci://cr.kgateway.dev/kgateway-dev/charts/kgateway \
  --namespace kgateway-system --version v2.2.1

# NFS Storage Class
kubectl apply -f k8s/base/storage/storageclass-nfs.yaml
```

---

#### Step 2 — Namespaces (must exist before everything else)

```bash
kubectl apply -f k8s/platform/namespace.yaml
kubectl apply -f k8s/dev/namespace.yaml
kubectl apply -f k8s/prod/namespace.yaml
```

---

#### Step 3 — Platform Gateway (must exist before routes and ArgoCD apps)

```bash
kubectl apply -f k8s/platform/gateway.yaml
kubectl apply -f k8s/platform/gateway-proxy.yaml
```

---

#### Step 4 — ArgoCD Bootstrap (apply once to start the GitOps engine)

```bash
# This registers the root App of Apps — ArgoCD then auto-creates all child apps
kubectl apply -f argocd/root-app-dev.yaml
kubectl apply -f argocd/root-app-prod.yaml
```

> After this step, ArgoCD will automatically deploy all Helm charts (auth, vehicle, maintenance, request, frontend, routes, postgres, redis, platform). Wait for all apps to reach **Synced / Healthy** before continuing.

---

#### Step 5 — Network Policies (apply after ArgoCD deploys all pods)

```bash
# Platform gateway egress rules (allows gateway to reach dev, prod, monitoring, argocd)
kubectl apply -f k8s/policies/networkpolicies/platform/allow-proxy-to-gateway.yaml
kubectl apply -f k8s/policies/networkpolicies/platform/allow-public-to-gateway-proxy.yaml
kubectl apply -f k8s/policies/networkpolicies/platform/allow-to-monitoring.yaml

# Grafana: allow gateway ingress + Prometheus egress + DNS egress
kubectl apply -f k8s/policies/networkpolicies/monitoring/allow-from-gateway.yaml
kubectl apply -f k8s/policies/networkpolicies/monitoring/reference-grant.yaml

# ArgoCD: allow gateway to reach argocd-server
kubectl apply -f k8s/policies/networkpolicies/argocd/allow-from-gateway.yaml

# Dev/Prod service discovery policies
kubectl apply -f k8s/policies/networkpolicies/dev/allow-service-discovery.yaml
kubectl apply -f k8s/policies/networkpolicies/prod/allow-service-discovery.yaml
```

---

#### Step 6 — Tool Exposures (routes for ops tooling, NOT in Helm charts)

```bash
# ArgoCD HTTPRoute — exposes ArgoCD UI via gateway at argocd.98.86.98.79.nip.io
kubectl apply -f k8s/platform/argocd-route.yaml
```

---

#### Step 7 — Monitoring Stack (Helm, managed outside ArgoCD)

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

helm install monitoring prometheus-community/kube-prometheus-stack \
  -n monitoring --create-namespace \
  --set grafana.grafana\.ini.server.domain=grafana.98.86.98.79.nip.io \
  --set grafana.grafana\.ini.server.root_url="http://grafana.98.86.98.79.nip.io/"
```

> If monitoring was already installed and you only need to update Grafana config after a restart:
> ```bash
> helm upgrade monitoring prometheus-community/kube-prometheus-stack \
>   -n monitoring --reuse-values \
>   --set grafana.grafana\.ini.server.domain=grafana.98.86.98.79.nip.io \
>   --set grafana.grafana\.ini.server.root_url="http://grafana.98.86.98.79.nip.io/"
> ```

---

### Quick Recovery (Cluster Restart Cheatsheet)

If the cluster is stopped and restarted, ArgoCD will re-sync all Helm apps automatically.
You only need to re-apply the `k8s/` files that are not Helm managed:

```bash
# Re-apply network policies (stateless, safe to re-apply anytime)
kubectl apply -f k8s/policies/networkpolicies/platform/
kubectl apply -f k8s/policies/networkpolicies/monitoring/
kubectl apply -f k8s/policies/networkpolicies/argocd/
kubectl apply -f k8s/policies/networkpolicies/dev/
kubectl apply -f k8s/policies/networkpolicies/prod/

# Re-apply ArgoCD exposure route
kubectl apply -f k8s/platform/argocd-route.yaml
```

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
- **Prod PostgreSQL**: 5Gi (dynamic provisioning)
- StorageClass: `fleetops-nfs` (already configured)

## Roadmap

- Helm + ArgoCD GitOps (Next)

## Gateway Deployment (kgateway Ingress)

To deploy the gateway and routing configuration:

### 1. Install kgateway
Install the standard Gateway API CRDs and kgateway:

```bash
kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.4.0/standard-install.yaml

helm repo add kgateway oci://cr.kgateway.dev/kgateway-dev/charts
helm repo update
helm install kgateway-crds oci://cr.kgateway.dev/kgateway-dev/charts/kgateway-crds \
  --namespace kgateway-system --create-namespace --version v2.2.1
helm install kgateway oci://cr.kgateway.dev/kgateway-dev/charts/kgateway \
  --namespace kgateway-system --version v2.2.1
```

### 2. Apply Platform Resources
```bash
kubectl apply -f k8s/platform/namespace.yaml
kubectl apply -f k8s/platform/gateway.yaml
kubectl apply -f k8s/platform/gateway-proxy.yaml
```

### 3. Deploy Environments (Example: Dev)
```bash
kubectl apply -f k8s/dev/namespace.yaml
kubectl apply -f k8s/dev/database/
kubectl apply -f k8s/dev/apps/
```

### 4. Configure HAProxy
Update external HAProxy configuration to use HTTP mode:

```haproxy
frontend fleetops_http
    bind *:80
    mode http
    default_backend fleetops_gateway

backend fleetops_gateway
    mode http
    balance roundrobin
    option httpchk GET /
    http-check expect status 200
    
    server worker1 172.31.43.240:30082 check
    server worker2 172.31.42.43:30082 check
```

### Architecture Flow
```
HAProxy (HTTP mode) → Nginx Proxy (NodePort 30082) → kgateway Envoy (NodePort 32708) → Services
```

Access via: `http://dev.98.86.98.79.nip.io`

## Network Policies Deployment

Network policies are implemented to control traffic between namespaces and ensure security isolation.

### Applied Policies

1. **Platform to Monitoring** (`k8s/policies/networkpolicies/platform/allow-to-monitoring.yaml`)
   - Allows `fleetops-gateway-proxy` pods to reach monitoring services on port 80
   - Enables Grafana access via the gateway

2. **Gateway Proxy** (`k8s/policies/networkpolicies/platform/allow-proxy-to-gateway.yaml`)
   - Allows `fleetops-gateway-proxy` to reach `fleetops-gateway` service
   - Includes DNS resolution rules for `kube-system` namespace
   - Allows egress to `fleetops-dev`, `fleetops-prod`, and `monitoring` namespaces

3. **Monitoring Ingress** (`k8s/policies/networkpolicies/monitoring/allow-from-gateway.yaml`)
   - Scoped to Grafana pods only (`app.kubernetes.io/name: grafana`)
   - Allows ingress from `fleetops-platform` namespace on ports 80 and 3000
   - Allows Grafana to reach Prometheus on port 9090
   - Includes DNS resolution rules
   - **Important**: Scoped to Grafana only to avoid breaking Prometheus's metric scraping capabilities

4. **ArgoCD Ingress** (`k8s/policies/networkpolicies/argocd/allow-from-gateway.yaml`)
   - Scoped to `argocd-server` pods only (`app.kubernetes.io/name: argocd-server`)
   - Allows ingress from `fleetops-platform` namespace on port `8080` (the actual targetPort)
   - Enables ArgoCD UI access via `http://argocd.98.86.98.79.nip.io`

### Apply Network Policies

```bash
kubectl apply -f k8s/policies/networkpolicies/platform/
kubectl apply -f k8s/policies/networkpolicies/monitoring/
kubectl apply -f k8s/policies/networkpolicies/argocd/
kubectl apply -f k8s/policies/networkpolicies/dev/
kubectl apply -f k8s/policies/networkpolicies/prod/
```

## Monitoring Stack Deployment

Prometheus and Grafana are deployed using the kube-prometheus-stack Helm chart.

### Installation

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update
helm install monitoring prometheus-community/kube-prometheus-stack -n monitoring --create-namespace
```

### Grafana Access

Grafana is accessible via a dedicated HTTPRoute with hostname-based routing:

- **URL**: `http://grafana.98.86.98.79.nip.io`
- **Default Credentials**: Get admin password with:
  ```bash
  kubectl get secret -n monitoring monitoring-grafana -o jsonpath="{.data.admin-password}" | base64 --decode
  ```

### HTTPRoute Configuration

The Grafana HTTPRoute is defined in `charts/routes/templates/httproutes.yaml` with:
- Dedicated hostname: `grafana.98.86.98.79.nip.io`
- WebSocket support via `appProtocol: kubernetes.io/ws`
- Backend: `monitoring-grafana` service on port 80

### WebSocket Support

WebSocket connections for Grafana Live features are enabled through:
1. **Nginx Proxy**: WebSocket upgrade headers in `k8s/platform/gateway-proxy.yaml`
2. **HTTPRoute**: `appProtocol: kubernetes.io/ws` in backendRefs
3. **Service**: `appProtocol: kubernetes.io/ws` on Grafana service port 80

### Default Credentials
- **admin1 / Admin@123** (ADMIN)
- **manager1 / Manager@123** (MANAGER)  
- **driver1 / Driver@123** (DRIVER)

## Phase 6 Deployment (ArgoCD Gateway Access)

ArgoCD is exposed via a standalone `HTTPRoute` deployed directly in the `argocd` namespace,
bound to the shared `fleetops-gateway`. No `ReferenceGrant` is needed because the route and
service are in the same namespace.

### ArgoCD Access

- **URL**: `http://argocd.98.86.98.79.nip.io`
- **Route File**: `k8s/platform/argocd-route.yaml`
- **NetworkPolicy**: `k8s/policies/networkpolicies/argocd/allow-from-gateway.yaml`

### Required: Disable ArgoCD Internal TLS Redirect

ArgoCD by default redirects all HTTP traffic to HTTPS. Since TLS is terminated at the
gateway level, the internal argocd-server must be set to insecure mode to prevent redirect loops.

**Apply once after ArgoCD is installed (or after cluster restart if the ConfigMap is lost):**

```bash
kubectl patch configmap argocd-cmd-params-cm -n argocd \
  --type merge \
  -p '{"data":{"server.insecure":"true"}}'

kubectl rollout restart deployment argocd-server -n argocd
kubectl rollout status deployment argocd-server -n argocd
```

### Apply ArgoCD Routing

```bash
kubectl apply -f k8s/policies/networkpolicies/argocd/allow-from-gateway.yaml
kubectl apply -f k8s/platform/argocd-route.yaml
```

---

## Access URLs Summary

| Service | URL | Notes |
|---|---|---|
| Dev App | `http://dev.98.86.98.79.nip.io` | ArgoCD managed |
| Prod App | `http://prod.98.86.98.79.nip.io` | ArgoCD managed |
| Grafana | `http://grafana.98.86.98.79.nip.io` | Manual helm install |
| ArgoCD | `http://argocd.98.86.98.79.nip.io` | Manual route + insecure patch |
