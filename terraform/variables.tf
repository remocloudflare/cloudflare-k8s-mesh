# =============================================================================
# variables.tf — all variable declarations live here.
# Non-sensitive values get sensible defaults; secrets + per-deployment IDs
# live in the gitignored terraform.tfvars (see terraform.tfvars.example).
# =============================================================================

# ── Cloudflare account / auth ────────────────────────────────────────
variable "cloudflare_api_token" {
  description = <<-EOT
    Cloudflare API token. Needs (account-scoped):
      * Cloudflare One Networks: Edit   (or Cloudflare Tunnel: Edit)
      * Zero Trust: Edit                (for HA config)
    NOTE: this is DIFFERENT from the token cloudflare-k8s uses (Zone DNS + Access).
  EOT
  type        = string
  sensitive   = true
}

variable "cloudflare_account_id" {
  description = "Cloudflare account ID that owns the Mesh node."
  type        = string
}

# ── Naming (owner prefix so it's obvious whose stack this is) ─────────
variable "name_prefix" {
  description = "Prefix for named Cloudflare objects (helps in shared accounts). Set \"\" to opt out."
  type        = string
  default     = ""
}

variable "mesh_node_name" {
  description = "Display name for the Mesh node (shown in Networking → Mesh)."
  type        = string
  default     = "k8s-mesh-node"
}

# ── HA on the connector config ────────────────────────────────────────
variable "ha_mode" {
  description = "High-availability mode for the Mesh node config. Single replica = false. Requires MASQUE device profile."
  type        = bool
  default     = false
}

# ── Advertised CIDR routes ────────────────────────────────────────────
# Each entry becomes a cloudflared_route (network CIDR + this Mesh node).
# In-cluster, the typical value is the Service CIDR — reachable-from-outside
# API endpoints, databases, etc. NEVER overlap 100.96.0.0/12 (Mesh CGNAT).
variable "mesh_routes" {
  description = <<-EOT
    Map of advertised routes into the mesh. Key = short label (used in comment),
    value = CIDR. Typical entries:
      * Service CIDR:  reach ClusterIP Services from remote Mesh clients
      * Pod CIDR:      reach Pods directly (only useful with a routable CNI)
      * Node CIDR:     reach the underlying nodes' internal IPs
    Split Tunnels on the WARP client device profile MUST include these CIDRs
    (or exclude them from the exclude list) or traffic never reaches the tun.
  EOT
  type        = map(string)
  default = {
    # EKS default Service CIDR — change to match your cluster:
    #   kubectl cluster-info dump | grep -i service-cluster-ip-range
    services = "172.20.0.0/16"
  }
}

variable "virtual_network_id" {
  description = <<-EOT
    Virtual network to attach the advertised routes to. Blank ("") = the
    account's default virtual network.
    A WARP client only sees routes in the vnet its device profile is bound to,
    so this MUST match the vnet your clients use or traffic silently never
    enters the tunnel. Check with `warp-cli vnet` on a client.
  EOT
  type        = string
  default     = ""
}

# ── Kubernetes side (optional) ────────────────────────────────────────
# When true, Terraform writes the MESH_NODE_TOKEN into a Secret in-cluster,
# so you never have to copy/paste the token by hand. When false (default),
# Terraform just prints an `output` and you `kubectl create secret ...`.
variable "create_k8s_secret" {
  description = "If true, create the cloudflare-mesh Secret in var.k8s_namespace with the enrollment token."
  type        = bool
  default     = false
}

variable "k8s_namespace" {
  description = "Namespace the mesh StatefulSet runs in. ArgoCD creates it."
  type        = string
  default     = "cloudflare-mesh"
}

variable "kube_config_path" {
  description = "Path to kubeconfig used by the kubernetes provider. Only matters if create_k8s_secret = true."
  type        = string
  default     = "~/.kube/config"
}

variable "kube_config_context" {
  description = "Kubeconfig context to use. Blank = current context. Only matters if create_k8s_secret = true."
  type        = string
  default     = ""
}
