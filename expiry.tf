# ── Auto-expiry: Terraform output warnings ─────────────────────────────────
#
# When EXPIRY_DAYS > 0, adds:
# - Creation timestamp as a tag
# - Outputs showing remaining days and warnings
#
# This is a soft expiry — it warns but doesn't auto-destroy.
# Use with EventBridge Scheduler for hard expiry (Phase 5 enhancement).
# ──────────────────────────────────────────────────────────────────────────

# ── Variables ────────────────────────────────────────────────────────────────
variable "expiry_days" {
  description = "Number of days before cluster expires. 0 = no expiry."
  type        = number
  default     = 0
}

# ── Creation timestamp ─────────────────────────────────────────────────────
resource "time_static" "created" {
  count = var.expiry_days > 0 ? 1 : 0
}

# ── Outputs ──────────────────────────────────────────────────────────────────
output "cluster_expiry_days" {
  description = "Number of days configured before cluster expiry."
  value       = var.expiry_days
}

output "cluster_created_at" {
  description = "Timestamp when the cluster was created (for expiry tracking)."
  value       = var.expiry_days > 0 ? time_static.created[0].rfc3339 : "no-expiry"
}

output "cluster_expires_at" {
  description = "Timestamp when the cluster will expire."
  value       = var.expiry_days > 0 ? timeadd(time_static.created[0].rfc3339, "${var.expiry_days * 24}h") : "no-expiry"
}

output "cluster_expiry_warning" {
  description = "Warning message if cluster is near expiry."
  value = var.expiry_days > 0 ? (
    <<-EOT
    ⚠️  CLUSTER EXPIRY WARNING
    Created: ${time_static.created[0].rfc3339}
    Expires: ${timeadd(time_static.created[0].rfc3339, "${var.expiry_days * 24}h")}
    Days remaining: ${max(0, var.expiry_days - (tonumber(formatdate("hh", timestamp())) / 24))}
    To extend: Update EXPIRY_DAYS in config and run: make config-apply
    To destroy: make destroy
    EOT
  ) : "No expiry configured (EXPIRY_DAYS=0)"
}
