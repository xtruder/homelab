path "github/token/project-*" {
  capabilities = ["read"]

  control_group = {
    ttl               = "15m"
    self_auth_allowed = false

    factor "homelab-approvers" {
      controlled_capabilities = ["read"]
      identity {
        group_names = ["homelab-approvers"]
        approvals   = 1
      }
    }
  }
}
