terraform {
  required_version = ">= 1.0"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

# Get the project number
data "google_project" "project" {
  project_id = var.project_id
}

# Create Workload Identity Pool for Red Hat OSD
resource "google_iam_workload_identity_pool" "osd_pool" {
  project                   = var.project_id
  workload_identity_pool_id = var.pool_id
  display_name             = var.pool_display_name
  description              = var.pool_description
  disabled                 = var.pool_disabled
}

# Create Workload Identity Pool Provider for Red Hat OSD OIDC
resource "google_iam_workload_identity_pool_provider" "osd_provider" {
  project                            = var.project_id
  workload_identity_pool_id         = google_iam_workload_identity_pool.osd_pool.workload_identity_pool_id
  workload_identity_pool_provider_id = var.provider_id
  display_name                       = var.provider_display_name
  description                        = var.provider_description
  disabled                           = var.provider_disabled

  # Attribute mapping for OSD service accounts
  attribute_mapping = {
    "google.subject"                = "assertion.sub"
    "attribute.namespace"           = "assertion['kubernetes.io']['namespace']"
    "attribute.service_account_name" = "assertion['kubernetes.io']['serviceaccount']['name']"
    "attribute.pod"                 = "assertion['kubernetes.io']['pod']['name']"
    "attribute.cluster"             = var.include_cluster_name ? "\"${var.osd_cluster_name}\"" : "\"\""
  }

  # Attribute condition to restrict access
  attribute_condition = var.attribute_condition != "" ? var.attribute_condition : (
    var.allowed_namespaces != [] ? 
    "attribute.namespace in ${jsonencode(var.allowed_namespaces)}" : 
    null
  )

  # OIDC configuration for Red Hat OSD
  oidc {
    issuer_uri        = var.osd_issuer_uri
    allowed_audiences = var.osd_allowed_audiences != [] ? var.osd_allowed_audiences : null
  }
}

# Create Service Accounts for OSD workloads
resource "google_service_account" "osd_service_accounts" {
  for_each = var.service_accounts

  project      = var.project_id
  account_id   = each.key
  display_name = each.value.display_name
  description  = each.value.description
}

# Grant roles to Service Accounts
resource "google_project_iam_member" "osd_sa_roles" {
  for_each = {
    for sa_role in local.sa_role_pairs : "${sa_role.sa_key}_${sa_role.role}" => sa_role
  }

  project = var.project_id
  role    = each.value.role
  member  = "serviceAccount:${google_service_account.osd_service_accounts[each.value.sa_key].email}"
}

# Workload Identity binding for each service account
resource "google_service_account_iam_member" "osd_wif_binding" {
  for_each = var.service_accounts

  service_account_id = google_service_account.osd_service_accounts[each.key].name
  role               = "roles/iam.workloadIdentityUser"
  member             = local.wif_members[each.key]
}

# Local variables for role assignments and WIF members
locals {
  # Flatten service accounts and their roles for iteration
  sa_role_pairs = flatten([
    for sa_key, sa_config in var.service_accounts : [
      for role in sa_config.roles : {
        sa_key = sa_key
        role   = role
      }
    ]
  ])

  # Generate WIF member strings for each service account
  wif_members = {
    for sa_key, sa_config in var.service_accounts : sa_key => (
      sa_config.osd_namespace != "" && sa_config.osd_service_account != "" ?
      "principal://iam.googleapis.com/${google_iam_workload_identity_pool.osd_pool.name}/subject/system:serviceaccount:${sa_config.osd_namespace}:${sa_config.osd_service_account}" :
      "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.osd_pool.name}/attribute.namespace/${sa_config.osd_namespace}"
    )
  }

  # Generate ConfigMap data for OSD
  configmap_data = {
    for sa_key, sa_config in var.service_accounts : sa_key => {
      gcp_service_account_email = google_service_account.osd_service_accounts[sa_key].email
      gcp_project_id            = var.project_id
      gcp_project_number        = data.google_project.project.number
      workload_identity_pool    = google_iam_workload_identity_pool.osd_pool.workload_identity_pool_id
      workload_identity_provider = google_iam_workload_identity_pool_provider.osd_provider.workload_identity_pool_provider_id
      osd_namespace             = sa_config.osd_namespace
      osd_service_account      = sa_config.osd_service_account
    }
  }
}

# Generate Kubernetes ConfigMap for OSD
resource "local_file" "osd_configmap" {
  count = var.generate_k8s_manifests ? 1 : 0

  filename = "${path.module}/k8s-manifests/configmap-wif-config.yaml"
  content  = yamlencode({
    apiVersion = "v1"
    kind       = "ConfigMap"
    metadata = {
      name      = "gcp-wif-config"
      namespace = var.k8s_namespace
    }
    data = {
      for sa_key, sa_data in local.configmap_data : sa_key => jsonencode(sa_data)
    }
  })
}

# Generate Kubernetes ServiceAccount manifests for OSD
resource "local_file" "osd_service_accounts" {
  for_each = var.generate_k8s_manifests ? var.service_accounts : {}

  filename = "${path.module}/k8s-manifests/sa-${each.value.osd_service_account}.yaml"
  content  = yamlencode({
    apiVersion = "v1"
    kind       = "ServiceAccount"
    metadata = {
      name      = each.value.osd_service_account
      namespace = each.value.osd_namespace
      annotations = {
        "iam.gke.io/gcp-service-account"                         = google_service_account.osd_service_accounts[each.key].email
        "eks.amazonaws.com/audience"                            = var.osd_allowed_audiences != [] ? var.osd_allowed_audiences[0] : "sts.googleapis.com"
        "serviceaccounts.openshift.io/cloud-credentials"        = "true"
      }
    }
  })
}