# GCP Workload Identity Federation for Red Hat OpenShift Dedicated (OSD)

This Terraform configuration sets up Workload Identity Federation (WIF) between Google Cloud Platform (GCP) and Red Hat OpenShift Dedicated (OSD) clusters, allowing OSD workloads to securely access GCP services without storing service account keys.

## Architecture Overview

```
Red Hat OSD Cluster                    Google Cloud Platform
┌──────────────────┐                  ┌────────────────────────┐
│                  │                  │                        │
│  Pod with SA     │ OIDC Token      │  Workload Identity    │
│  ┌────────────┐  │ ───────────────►│  Pool & Provider      │
│  │ Workload   │  │                  │                        │
│  └────────────┘  │                  │  ┌──────────────┐     │
│                  │                  │  │ IAM Binding  │     │
│  Service Account │                  │  └──────────────┘     │
│  (Kubernetes)    │                  │           │            │
│                  │                  │           ▼            │
│                  │                  │  ┌──────────────┐     │
└──────────────────┘                  │  │ GCP Service  │     │
                                      │  │   Account    │     │
                                      │  └──────────────┘     │
                                      │           │            │
                                      │           ▼            │
                                      │  ┌──────────────┐     │
                                      │  │ GCP Resources│     │
                                      │  │ (GCS, BQ,    │     │
                                      │  │  Pub/Sub)    │     │
                                      │  └──────────────┘     │
                                      └────────────────────────┘
```

## Prerequisites

### 1. GCP Requirements
- GCP Project with billing enabled
- Required APIs enabled:
  - IAM API (`iam.googleapis.com`)
  - Security Token Service API (`sts.googleapis.com`)
  - IAM Service Account Credentials API (`iamcredentials.googleapis.com`)
- Appropriate IAM permissions (Project Owner or IAM Admin)

### 2. Red Hat OSD Requirements
- Access to Red Hat OpenShift Dedicated cluster
- Cluster admin permissions
- OIDC provider endpoint accessible from GCP
- `oc` CLI tool installed and configured

### 3. Local Requirements
- Terraform >= 1.0
- `gcloud` CLI installed and authenticated
- `kubectl` or `oc` CLI for OSD cluster access

## Step-by-Step Setup

### Step 1: Enable GCP APIs

```bash
# Set your project
export PROJECT_ID="your-gcp-project-id"
gcloud config set project $PROJECT_ID

# Enable required APIs
gcloud services enable \
  iam.googleapis.com \
  sts.googleapis.com \
  iamcredentials.googleapis.com \
  cloudresourcemanager.googleapis.com
```

### Step 2: Get OSD Cluster OIDC Information

```bash
# Login to your OSD cluster
oc login --server=https://api.your-osd-cluster.openshift.com:6443

# Get the OIDC issuer URI
ISSUER_URI=$(oc get authentication.config.openshift.io cluster -o json | jq -r .spec.serviceAccountIssuer)
echo "OIDC Issuer URI: $ISSUER_URI"

# Alternative method - check OAuth configuration
oc get oauth cluster -o json | jq -r .spec.identityProviders
```

### Step 3: Configure Terraform Variables

```bash
# Copy the example file
cp terraform.tfvars.example terraform.tfvars

# Edit terraform.tfvars with your values
vi terraform.tfvars
```

Key configurations to update:
- `project_id`: Your GCP project ID
- `osd_issuer_uri`: The OIDC issuer URI from Step 2
- `osd_cluster_name`: Your OSD cluster name
- `allowed_namespaces`: List of OSD namespaces allowed to use WIF
- `service_accounts`: Map of GCP service accounts and their OSD bindings

### Step 4: Initialize and Apply Terraform

```bash
# Initialize Terraform
terraform init

# Review the plan
terraform plan

# Apply the configuration
terraform apply
```

### Step 5: Configure OSD Cluster

After Terraform completes, configure your OSD cluster:

```bash
# For each service account created, run:
kubectl create namespace <namespace> --dry-run=client -o yaml | kubectl apply -f -
kubectl create serviceaccount <sa-name> -n <namespace>

# Apply the generated Kubernetes manifests (if generated)
kubectl apply -f k8s-manifests/
```

### Step 6: Test the Configuration

Deploy a test pod to verify WIF is working:

```bash
# Create a test pod
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: wif-test
  namespace: production
spec:
  serviceAccountName: gcs-workload-sa
  containers:
  - name: test
    image: google/cloud-sdk:latest
    command: ["/bin/sh"]
    args: ["-c", "sleep 3600"]
    env:
    - name: GOOGLE_APPLICATION_CREDENTIALS
      value: /var/run/secrets/workload-identity/token
EOF

# Exec into the pod
kubectl exec -it wif-test -n production -- /bin/bash

# Inside the pod, test GCP access
gcloud auth list
gsutil ls
```

## Configuration Examples

### Example 1: Storage Access from OSD

```hcl
service_accounts = {
  "storage-sa" = {
    display_name        = "Storage Access SA"
    description         = "Access GCS from OSD workloads"
    roles = [
      "roles/storage.objectAdmin"
    ]
    osd_namespace       = "data-pipeline"
    osd_service_account = "gcs-accessor"
  }
}
```

### Example 2: Multi-Service Configuration

```hcl
service_accounts = {
  "app-sa" = {
    display_name        = "Application SA"
    description         = "Main application service account"
    roles = [
      "roles/storage.objectViewer",
      "roles/bigquery.dataViewer",
      "roles/pubsub.subscriber"
    ]
    osd_namespace       = "production"
    osd_service_account = "app-workload"
  }
}
```

### Example 3: Namespace-Level Access

```hcl
# Allow all service accounts in specific namespaces
allowed_namespaces = ["production", "staging"]
attribute_condition = "attribute.namespace in ['production', 'staging']"
```

## Using WIF in Your Applications

### Python Example

```python
from google.auth import default
from google.cloud import storage

# Credentials are automatically obtained via WIF
credentials, project = default()
client = storage.Client(credentials=credentials, project=project)

# Use the client normally
buckets = client.list_buckets()
```

### Java Example

```java
import com.google.cloud.storage.Storage;
import com.google.cloud.storage.StorageOptions;

// Credentials are automatically obtained
Storage storage = StorageOptions.getDefaultInstance().getService();
```

### Go Example

```go
import (
    "context"
    "cloud.google.com/go/storage"
)

ctx := context.Background()
// Client automatically uses WIF credentials
client, err := storage.NewClient(ctx)
```

## Troubleshooting

### Common Issues and Solutions

1. **"Permission denied" when accessing GCP resources**
   - Verify the GCP service account has the correct IAM roles
   - Check the workload identity binding is correct
   - Ensure the OSD service account is annotated properly

2. **"Invalid token" or authentication errors**
   - Verify the OIDC issuer URI is correct and accessible
   - Check the audience configuration matches
   - Ensure the OSD cluster's OIDC endpoint is publicly accessible

3. **"Attribute condition does not match"**
   - Review the attribute condition expression
   - Check the namespace and service account names match exactly
   - Use `gcloud logging read` to debug attribute values

### Debugging Commands

```bash
# Check WIF pool status
gcloud iam workload-identity-pools describe osd-workload-pool \
  --location=global

# Check provider configuration
gcloud iam workload-identity-pools providers describe osd-provider \
  --workload-identity-pool=osd-workload-pool \
  --location=global

# View IAM bindings
gcloud iam service-accounts get-iam-policy SERVICE_ACCOUNT_EMAIL

# Check OSD service account annotations
kubectl describe sa SERVICE_ACCOUNT_NAME -n NAMESPACE

# Test token exchange manually
kubectl run -it --rm debug --image=curlimages/curl --restart=Never -- sh
# Inside the pod:
TOKEN=$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)
curl -X POST https://sts.googleapis.com/v1/token ...
```

### Monitoring and Logging

```bash
# View audit logs for WIF usage
gcloud logging read "resource.type=iam_role AND protoPayload.serviceName=sts.googleapis.com"

# Monitor service account usage
gcloud logging read "protoPayload.authenticationInfo.principalEmail=SERVICE_ACCOUNT_EMAIL"
```

## Security Best Practices

1. **Principle of Least Privilege**
   - Grant only necessary IAM roles to service accounts
   - Use separate service accounts for different workloads

2. **Namespace Isolation**
   - Restrict WIF access to specific namespaces
   - Use attribute conditions for fine-grained control

3. **Regular Audits**
   - Review IAM bindings regularly
   - Monitor unusual authentication patterns
   - Audit service account usage

4. **Token Lifetime**
   - Configure appropriate token expiration times
   - Implement token refresh in long-running applications

5. **Network Security**
   - Ensure OIDC endpoints use HTTPS
   - Consider private endpoints for sensitive workloads

## Clean Up

To remove all resources:

```bash
# Remove Kubernetes resources from OSD
kubectl delete -f k8s-manifests/

# Destroy Terraform resources
terraform destroy

# Disable APIs (optional)
gcloud services disable \
  sts.googleapis.com \
  iamcredentials.googleapis.com
```

## Additional Resources

- [GCP Workload Identity Federation Documentation](https://cloud.google.com/iam/docs/workload-identity-federation)
- [Red Hat OpenShift Documentation](https://docs.openshift.com/)
- [OpenShift Service Accounts](https://docs.openshift.com/container-platform/latest/authentication/using-service-accounts.html)
- [GCP IAM Best Practices](https://cloud.google.com/iam/docs/best-practices)

## Support

For issues specific to:
- GCP WIF: Check [GCP Support](https://cloud.google.com/support)
- Red Hat OSD: Contact [Red Hat Support](https://access.redhat.com/support)
- Terraform: See [Terraform Registry](https://registry.terraform.io/providers/hashicorp/google/latest/docs)
