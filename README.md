# FleetOps Deployments — EKS-Native

This repository contains all Kubernetes manifests and Helm charts for deploying FleetOps onto Amazon EKS.

> **Architecture shift**: Previously deployed on a manually managed Kubernetes cluster using in-cluster Postgres, Redis, Sealed Secrets, and kgateway. Everything is now AWS-managed.

---

## What Changed (Before vs After)

| Component | Before (Manual K8s) | After (AWS Managed) |
| :--- | :--- | :--- |
| **Database** | Postgres StatefulSet in-cluster | AWS RDS (db.t3.micro, KMS-encrypted) |
| **Cache** | Redis Deployment in-cluster | AWS ElastiCache (cache.t3.micro) |
| **Secrets** | Bitnami Sealed Secrets | External Secrets Operator → Secrets Manager |
| **Ingress** | kgateway + HTTPRoute | AWS ALB Controller + Ingress |
| **Images** | Docker Hub (`docker.io/johann2003/...`) | Amazon ECR |
| **Domain** | `*.98.86.98.79.nip.io` (raw IP) | `fleetops.website` (Route53 + ACM) |
| **TLS** | Not configured | ACM cert, terminated at ALB |
| **AWS Access** | Not applicable | IRSA (pod-level IAM via OIDC) |

---

## Directory Structure

```
fleetops-deployments/
│
├── k8s/                           ← Raw Kubernetes manifests
│   ├── platform/
│   │   ├── namespace.yaml         ← fleetops-prod + external-secrets namespaces
│   │   ├── service-account.yaml   ← IRSA-annotated ServiceAccount (fleetops-app)
│   │   └── external-secrets.yaml  ← ClusterSecretStore + ExternalSecrets (DB, JWT, Redis)
│   │
│   └── prod/
│       └── apps/
│           ├── ingress.yaml       ← AWS ALB Ingress (replaces kgateway HTTPRoute)
│           ├── auth-service/
│           ├── vehicle-service/
│           ├── maintenance-service/
│           ├── request-service/
│           └── frontend/
│
├── charts/                        ← Helm charts (one per service)
│   ├── common/                    ← Shared helpers (_helpers.tpl)
│   ├── auth-service/
│   ├── vehicle-service/
│   ├── maintenance-service/       ← Includes Bedrock config (Phase 7)
│   ├── request-service/
│   └── frontend/
│
└── argocd/                        ← ArgoCD GitOps (Phase 3+)
    ├── root-app-prod.yaml
    └── apps/
```

---

## How Secrets Work (No Sealed Secrets Needed)

```
AWS Secrets Manager
  fleetops/dev/db     → username, password, host
  fleetops/dev/jwt    → jwt_secret

AWS SSM Parameter Store
  /fleetops/dev/redis/endpoint  → Redis host

         ↓  (External Secrets Operator syncs every 1h)

Kubernetes Secrets (created automatically by ESO)
  fleetops-postgres-secret  → POSTGRES_USER, POSTGRES_PASSWORD, POSTGRES_HOST
  fleetops-app-secret       → JWT_SECRET
  fleetops-redis-secret     → REDIS_HOST

         ↓  (Pods reference via secretKeyRef)

Spring Boot env vars
  SPRING_DATASOURCE_URL      = jdbc:postgresql://$(POSTGRES_HOST):5432/<db>
  SPRING_DATASOURCE_USERNAME = <from secret>
  SPRING_DATASOURCE_PASSWORD = <from secret>
  SPRING_REDIS_HOST          = <from secret>
  JWT_SECRET                 = <from secret>
```

---

## Deployment Order (Phase 3)

```bash
# 1. Apply platform resources (namespaces, IRSA SA, ESO config)
kubectl apply -f k8s/platform/

# 2. Wait for ESO to sync secrets (usually < 30 seconds)
kubectl get externalsecret -n fleetops-prod

# 3. Deploy services via Helm
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
ECR_REGISTRY="${ACCOUNT_ID}.dkr.ecr.us-east-1.amazonaws.com"

for svc in auth-service vehicle-service maintenance-service request-service frontend; do
  helm upgrade --install $svc ./charts/$svc \
    -f ./charts/$svc/values-prod.yaml \
    --set image.registry=$ECR_REGISTRY \
    --namespace fleetops-prod
done

# 4. Apply ALB Ingress (after services are running)
kubectl apply -f k8s/prod/apps/ingress.yaml

# 5. Get ALB DNS name → add to Route53 as ALB alias record
kubectl get ingress -n fleetops-prod
```

---

## Update Service Account IRSA ARN

After `terraform apply`, get the IRSA role ARN and update the ServiceAccount:

```bash
# Get ARN from Terraform output
IRSA_ARN=$(terraform -chdir=../fleetops-infra/terraform/environments/dev output -raw app_irsa_role_arn)

# Patch the service account
kubectl annotate serviceaccount fleetops-app \
  -n fleetops-prod \
  eks.amazonaws.com/role-arn=$IRSA_ARN \
  --overwrite
```

Or update `k8s/platform/service-account.yaml` with the actual ARN before applying.

---

## ArgoCD GitOps (Phase 3+)

ArgoCD is pre-configured in `argocd/` and points to this repo. To enable:

```bash
# Install ArgoCD into EKS
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# Apply the root app
kubectl apply -f argocd/root-app-prod.yaml
```

ArgoCD will then manage all deployments via GitOps — any push to this repo triggers a sync.

---

## AI Maintenance Advisor (Phase 7)

The `maintenance-service` is pre-configured for Amazon Bedrock:

```yaml
# In charts/maintenance-service/values.yaml
config:
  bedrockModelId: "anthropic.claude-haiku-20240307-v1:0"
  awsRegion: "us-east-1"
```

The pod's IRSA role (`fleetops-app`) already includes `bedrock:InvokeModel` permission. No API keys needed — access is granted via IRSA.
