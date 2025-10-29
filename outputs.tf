output "pool_id" {
  description = "The ID of the workload identity pool"
  value       = google_iam_workload_identity_pool.osd_pool.id
}

output "pool_name" {
  description = "The full resource name of the workload identity pool"
  value       = google_iam_workload_identity_pool.osd_pool.name
}

output "provider_id" {
  description = "The ID of the workload identity provider"
  value       = google_iam_workload_identity_pool_provider.osd_provider.id
}

output "provider_name" {
  description = "The full resource name of the workload identity provider"
  value       = google_iam_workload_identity_pool_provider.osd_provider.name
}

output "project_number" {
  description = "The GCP project number"
  value       = data.google_project.project.number
}

output "service_accounts" {
  description = "Details of created GCP service accounts"
  value = {
    for key, sa in google_service_account.osd_service_accounts : key => {
      email      = sa.email
      unique_id  = sa.unique_id
      name       = sa.name
      member     = local.wif_members[key]
    }
  }
}

output "workload_identity_provider_path" {
  description = "The provider resource path for configuring OSD workloads"
  value       = "projects/${data.google_project.project.number}/locations/global/workloadIdentityPools/${var.pool_id}/providers/${var.provider_id}"
}

output "osd_configuration" {
  description = "Configuration values for OSD cluster"
  value = {
    issuer_uri             = var.osd_issuer_uri
    cluster_name           = var.osd_cluster_name
    allowed_namespaces     = var.allowed_namespaces
    workload_identity_pool = var.pool_id
    provider_id            = var.provider_id
  }
}

output "kubectl_commands" {
  description = "Kubectl commands to configure OSD cluster"
  value = {
    for sa_key, sa_config in var.service_accounts : sa_key => {
      create_namespace = "kubectl create namespace ${sa_config.osd_namespace} --dry-run=client -o yaml | kubectl apply -f -"
      create_sa       = "kubectl create serviceaccount ${sa_config.osd_service_account} -n ${sa_config.osd_namespace}"
      annotate_sa     = "kubectl annotate serviceaccount ${sa_config.osd_service_account} -n ${sa_config.osd_namespace} iam.gke.io/gcp-service-account=${google_service_account.osd_service_accounts[sa_key].email}"
    }
  }
}

output "token_exchange_command" {
  description = "Command to test token exchange from OSD"
  value = <<-EOT
    # Run this command from within a pod using the service account in OSD:
    
    PROJECT_NUMBER="${data.google_project.project.number}"
    POOL_ID="${var.pool_id}"
    PROVIDER_ID="${var.provider_id}"
    SA_EMAIL="<GCP_SERVICE_ACCOUNT_EMAIL>"
    
    # Get the OSD service account token
    OSD_TOKEN=$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)
    
    # Exchange for GCP access token
    curl -X POST https://sts.googleapis.com/v1/token \
      -H "Content-Type: application/x-www-form-urlencoded" \
      -d "grant_type=urn:ietf:params:oauth:grant-type:token-exchange" \
      -d "audience=//iam.googleapis.com/projects/$PROJECT_NUMBER/locations/global/workloadIdentityPools/$POOL_ID/providers/$PROVIDER_ID" \
      -d "subject_token_type=urn:ietf:params:oauth:token-type:jwt" \
      -d "requested_token_type=urn:ietf:params:oauth:token-type:access_token" \
      -d "scope=https://www.googleapis.com/auth/cloud-platform" \
      -d "subject_token=$OSD_TOKEN"
  EOT
}
