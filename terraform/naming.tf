# =============================================================================
# naming.tf — single source of truth for object names.
# One edit to var.name_prefix renames everything consistently.
# =============================================================================
locals {
  name_prefix = var.name_prefix != "" ? "${var.name_prefix}-" : ""
  node_name   = "${local.name_prefix}${var.mesh_node_name}"
}
