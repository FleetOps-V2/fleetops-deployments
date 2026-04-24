# FleetOps Deployments

Dedicated deployment repository for FleetOps runtime assets.

This repo is intentionally separate from application repos (`fleetops-frontend`, `fleetops-auth-service`, `fleetops-vehicle-service`, `fleetops-request-service`, `fleetops-maintenance-service`) so deployment changes can be versioned, reviewed, and promoted independently.

## Why Separate Deployment Repo

- decouples app code lifecycle from infra/deployment lifecycle
- enables controlled environment promotion (dev -> prod)
- prepares for GitOps workflows (ArgoCD) and chart-driven releases (Helm)
- keeps security/network/policy assets centralized

## Namespace Strategy

- `fleetops-platform`: shared platform components (gateway, ingress, observability, shared ops tooling later)
- `fleetops-dev`: development deployments and integration testing
- `fleetops-prod`: production deployments and promotion targets

Dev and prod are separated to isolate risk, credentials, rollout timing, and policy enforcement.

## Repository Layout (Refined Phase 1)

```text
fleetops-deployments/
  README.md
  k8s/
    base/
      storage/
        storageclass-nfs.yaml
        postgres-pv.yaml
        postgres-pvc-dev.yaml
        postgres-pvc-prod.yaml
    platform/
      namespace.yaml
    dev/
      namespace.yaml
      database/
        postgres-configmap.yaml
        postgres-secret.yaml
        postgres-service.yaml
        postgres-statefulset.yaml
      apps/
        .gitkeep
    prod/
      namespace.yaml
      database/
        postgres-configmap.yaml
        postgres-secret.yaml
        postgres-service.yaml
        postgres-statefulset.yaml
      apps/
        .gitkeep
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

1. Namespaces
   - `k8s/platform/namespace.yaml`
   - `k8s/dev/namespace.yaml`
   - `k8s/prod/namespace.yaml`
2. Storage (dynamic provisioner mode)
   - `k8s/base/storage/storageclass-nfs.yaml`
   - `k8s/base/storage/postgres-pvc-dev.yaml`
   - `k8s/base/storage/postgres-pvc-prod.yaml`
3. Storage (static provisioning fallback)
   - `k8s/base/storage/storageclass-nfs.yaml`
   - `k8s/base/storage/postgres-pv.yaml`
   - `k8s/base/storage/postgres-pvc-dev.yaml`
   - `k8s/base/storage/postgres-pvc-prod.yaml`
4. Environment database config
   - `k8s/dev/database/postgres-secret.yaml`
   - `k8s/dev/database/postgres-configmap.yaml`
   - `k8s/prod/database/postgres-secret.yaml`
   - `k8s/prod/database/postgres-configmap.yaml`
5. Environment database runtime
   - `k8s/dev/database/postgres-service.yaml`
   - `k8s/dev/database/postgres-statefulset.yaml`
   - `k8s/prod/database/postgres-service.yaml`
   - `k8s/prod/database/postgres-statefulset.yaml`

## Assumptions

- NFS placeholders must be replaced:
  - `NFS_SERVER_IP`
  - `/exports/fleetops/dev`
  - `/exports/fleetops/prod`
- static PV fallback uses `5Gi` for dev and prod with `Retain` reclaim policy
- secret values are templates only, not real credentials
- config/secret keys align to `cloudcart-infra` conventions:
  - `POSTGRES_USER`
  - `POSTGRES_PASSWORD`
  - `POSTGRES_DB`
  - `DB_HOST`
  - `DB_PORT`

## Roadmap

- Phase 2: app Deployments, Services, probes
- Phase 3: kgateway routing
- Phase 4: NetworkPolicies
- Phase 5: Helm + ArgoCD GitOps
