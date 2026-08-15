# =============================================================================
# routes.tf — advertise CIDRs into the mesh through this node.
# One resource per entry in var.mesh_routes.
#
# VIRTUAL NETWORKS MATTER. A route is the triple
# (network CIDR + tunnel_id + virtual_network_id). A client only sees routes
# belonging to the virtual network its device profile is bound to. Leaving
# virtual_network_id unset puts these routes in the account's DEFAULT vnet --
# fine only if your clients are also on the default vnet.
#
# If everything times out from a laptop while node-to-node works, check the
# vnet binding BEFORE blaming Split Tunnels:
#   warp-cli vnet          # which vnet is this device on?
# Dashboard: Networking > Routes shows the vnet column per route.
#
# Set var.virtual_network_id to pin these routes to a specific vnet.
# =============================================================================

resource "cloudflare_zero_trust_tunnel_cloudflared_route" "mesh" {
  for_each = var.mesh_routes

  account_id = var.cloudflare_account_id
  tunnel_id  = cloudflare_zero_trust_tunnel_warp_connector.mesh.id
  network    = each.value
  comment    = "k8s mesh: ${each.key}"

  # null => the account's default virtual network.
  virtual_network_id = var.virtual_network_id != "" ? var.virtual_network_id : null
}
