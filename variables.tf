# GCP Project Configuration
variable "project_id" {
  description = "The GCP project ID"
  type        = string
}

variable "region" {
  description = "The GCP region"
  type        = string
  default     = "us-central1"
}

# Workload Identity Pool Configuration
variable "pool_id" {
  description = "The ID for the workload identity pool"
  type        = string
  default     = "osd-workload-pool"
}

variable "pool_display_name" {
  description = "Display name for the workload identity pool"
  type        = string
  default     = "Red Hat OSD Workload Identity Pool"
}

variable "pool_description" {
  description = "Description for the workload identity pool"
  type        = string
  default     = "Workload identity pool for Red Hat OpenShift Dedicated clusters"
}

variable "pool_disabled" {
  description = "Whether the pool is disabled"
  type        = bool
  default     = false
}

# Workload Identity Provider Configuration
variable "provider_id" {
  description = "The ID for the workload identity provider"
  type        = string
  default     = "osd-provider"
}

variable "provider_display_name" {
  description = "Display name for the workload identity provider"
  type        = string
  default     = "Red Hat OSD OIDC Provider"
}

variable "provider_description" {
  description = "Description for the workload identity provider"
  type        = string
  default     = "OIDC provider for Red Hat OpenShift Dedicated cluster"
}

variable "provider_disabled" {
  description = "Whether the provider is disabled"
  type        = bool
  default     = false
}

# Red Hat OSD Configuration
variable "osd_issuer_uri" {
  description = "The OIDC issuer URI for your Red Hat OSD cluster"
  type        = string
}

variable "osd_cluster_name" {
  description = "Name of the Red Hat OSD cluster"
  type        = string
}

variable "osd_allowed_audiences" {
  description = "List of allowed audiences for OIDC provider (optional, defaults to empty which accepts all)"
  type        = list(string)
  default     = []
}

variable "include_cluster_name" {
  description = "Whether to include cluster name in attribute mapping"
  type        = bool
  default     = true
}

# Access Control
variable "allowed_namespaces" {
  description = "List of OSD namespaces allowed to use workload identity (empty allows all)"
  type        = list(string)
  default     = []
}

variable "attribute_condition" {
  description = "Custom CEL expression for attribute condition (overrides allowed_namespaces if set)"
  type        = string
  default     = ""
}

# Service Account Configuration
variable "service_accounts" {
  description = "Map of GCP service accounts to create and bind to OSD service accounts"
  type = map(object({
    display_name        = string
    description        = string
    roles              = list(string)
    osd_namespace      = string
    osd_service_account = string
  }))
  default = {}
}

# Kubernetes Manifest Generation
variable "generate_k8s_manifests" {
  description = "Whether to generate Kubernetes manifest files for OSD"
  type        = bool
  default     = true
}

variable "k8s_namespace" {
  description = "Default Kubernetes namespace for resources"
  type        = string
  default     = "default"
}

variable "generate_sample_deployment" {
  description = "Whether to generate a sample deployment manifest"
  type        = bool
  default     = false
}
