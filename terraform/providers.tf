# ── Provider + Terraform settings ─────────────────────────────────────
terraform {
  required_version = ">= 1.5"
  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 5.0"
    }
    # Optional: only used if var.create_k8s_secret = true. Keeps the token
    # off local disk by pushing it straight into the cluster.
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.30"
    }
  }
}

provider "cloudflare" {
  api_token = var.cloudflare_api_token
}

# The kubernetes provider is only exercised when var.create_k8s_secret = true.
# Reads standard KUBECONFIG env / ~/.kube/config by default. Override via the
# kube_* variables if you need to point at a different cluster/context.
provider "kubernetes" {
  config_path    = var.kube_config_path
  config_context = var.kube_config_context != "" ? var.kube_config_context : null
}
