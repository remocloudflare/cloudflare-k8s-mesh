# =============================================================================
# outputs.tf
# =============================================================================

output "mesh_node_id" {
  description = "ID of the Mesh node (WARP Connector tunnel)."
  value       = cloudflare_zero_trust_tunnel_warp_connector.mesh.id
}

output "mesh_node_name" {
  description = "Display name of the Mesh node."
  value       = cloudflare_zero_trust_tunnel_warp_connector.mesh.name
}

output "mesh_node_token" {
  description = "Enrollment token. Pass as MESH_NODE_TOKEN to the cloudflare/mesh container. SENSITIVE."
  value       = data.cloudflare_zero_trust_tunnel_warp_connector_token.mesh.token
  sensitive   = true
}

output "advertised_routes" {
  description = "Map of label => CIDR advertised through this Mesh node."
  value       = { for k, r in cloudflare_zero_trust_tunnel_cloudflared_route.mesh : k => r.network }
}

# Copy-paste helper for the manual (create_k8s_secret = false) path.
output "kubectl_secret_command" {
  description = "Create the k8s Secret from the token. Reveal the token first with `terraform output -raw mesh_node_token`."
  value       = "kubectl -n ${var.k8s_namespace} create secret generic cloudflare-mesh --from-literal=MESH_NODE_TOKEN=\"$(terraform output -raw mesh_node_token)\""
}
