# =============================================================================
# routes.tf — advertise CIDRs into the mesh through this node.
# One resource per entry in var.mesh_routes.
#
# NOTE: Unlike the "site" mesh-setup module, this k8s-side deployment does NOT
# attach routes to a Virtual Network by default. Hostname routes and CIDR
# routes on Mesh v2 use a single global namespace; VNets are legacy from the
# WARP Connector era and only needed when you have overlapping ranges. Add a
# virtual_network_id to these resources if you know you need one.
# =============================================================================

resource "cloudflare_zero_trust_tunnel_cloudflared_route" "mesh" {
  for_each = var.mesh_routes

  account_id = var.cloudflare_account_id
  tunnel_id  = cloudflare_zero_trust_tunnel_warp_connector.mesh.id
  network    = each.value
  comment    = "k8s mesh: ${each.key}"
}
