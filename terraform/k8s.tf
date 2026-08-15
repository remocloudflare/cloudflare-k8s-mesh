# =============================================================================
# k8s.tf — OPTIONAL Kubernetes Secret creation.
#
# When var.create_k8s_secret = true (default false), Terraform writes the
# enrollment token into a Secret named `cloudflare-mesh` in var.k8s_namespace.
# The StatefulSet in manifests/mesh.yml consumes this Secret directly.
#
# When false, Terraform stays hands-off — copy the token from `terraform
# output -raw mesh_node_token` and run `kubectl create secret generic ...`
# yourself (recommended for CI/GitOps pipelines that keep TF out of the
# cluster-write path).
#
# NOTE ON STATE: the token reaches this Secret via a data source, so it is
# written to terraform.tfstate regardless of which path you pick. This option
# removes a copy/paste step, not a secret from disk.
# =============================================================================

# The Secret needs its namespace to exist FIRST. ArgoCD also creates this
# namespace (syncOptions: CreateNamespace=true), but only at sync time -- which
# is after `terraform apply`. Without this resource, a TF-first run on a fresh
# cluster fails with `namespaces "cloudflare-mesh" not found`.
#
# The PSA labels match argocd/application.yaml's managedNamespaceMetadata
# exactly, so ArgoCD adopts this namespace without drift.
resource "kubernetes_namespace" "mesh" {
  count = var.create_k8s_secret ? 1 : 0

  metadata {
    name = var.k8s_namespace
    labels = {
      "pod-security.kubernetes.io/enforce" = "privileged"
      "pod-security.kubernetes.io/warn"    = "privileged"
      "pod-security.kubernetes.io/audit"   = "privileged"
    }
  }
}

resource "kubernetes_secret" "mesh_token" {
  count = var.create_k8s_secret ? 1 : 0

  metadata {
    name      = "cloudflare-mesh"
    namespace = kubernetes_namespace.mesh[0].metadata[0].name
    labels = {
      "app.kubernetes.io/name"       = "cloudflare-mesh"
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }

  data = {
    MESH_NODE_TOKEN = data.cloudflare_zero_trust_tunnel_warp_connector_token.mesh.token
  }

  type = "Opaque"
}
