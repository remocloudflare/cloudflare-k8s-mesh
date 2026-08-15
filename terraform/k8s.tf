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
# =============================================================================

resource "kubernetes_secret" "mesh_token" {
  count = var.create_k8s_secret ? 1 : 0

  metadata {
    name      = "cloudflare-mesh"
    namespace = var.k8s_namespace
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
