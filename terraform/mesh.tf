# =============================================================================
# mesh.tf — the Cloudflare-side Mesh node objects:
#   1. the Mesh node (WARP Connector tunnel object)
#   2. its HA config
#   3. (data) the enrollment token used by the k8s Secret
#
# This manages the CLOUDFLARE side only. The Pod running cloudflare/mesh in
# the cluster consumes MESH_NODE_TOKEN from a Secret to enroll itself.
# =============================================================================

# The Mesh node object (API terminology: WARP Connector tunnel).
resource "cloudflare_zero_trust_tunnel_warp_connector" "mesh" {
  account_id = var.cloudflare_account_id
  name       = local.node_name
}

# HA config for the Mesh node. HA is meaningful only when ≥2 replicas share
# the same token AND the device profile is MASQUE — see README.
resource "cloudflare_zero_trust_tunnel_warp_connector_config" "mesh" {
  account_id = var.cloudflare_account_id
  tunnel_id  = cloudflare_zero_trust_tunnel_warp_connector.mesh.id
  ha_mode    = var.ha_mode
}

# Enrollment token — pass as MESH_NODE_TOKEN to the container. Exposed via a
# data source in the CF v5 provider (not an attribute on the tunnel resource).
data "cloudflare_zero_trust_tunnel_warp_connector_token" "mesh" {
  account_id = var.cloudflare_account_id
  tunnel_id  = cloudflare_zero_trust_tunnel_warp_connector.mesh.id
}
