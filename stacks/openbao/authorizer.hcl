server {
  listen_address   = "0.0.0.0:8080"
  public_origin    = "https://baoauthz.${env.DOMAIN_NAME}"
  insecure_cookies = false
  static_directory = ""
  session_ttl      = "168h"
}

storage {
  database_path       = "/var/lib/openbao-authorizer/app.db"
  encryption_key_file = "/run/secrets/authorizer_encryption_key"
}

openbao {
  address               = "http://openbao:8200"
  namespace             = ""
  ca_file               = ""
  authorizer_token_file = "/run/secrets/openbao_authorizer_token"
  approver_policy       = "openbao-authorizer-approver"
}

# Approvers sign in to OpenBao from the browser, so this is the public address;
# setup-openbao.sh allows the authorizer origin in OpenBao's CORS config.
approver_login {
  openbao_address = "https://bao.${env.DOMAIN_NAME}"
  method "userpass" {
    label = "Username & password"
  }
}

# Session Tokens minted by the opencode plugin.
requester "opencode" {
  token_role = "opencode-session"
}

# Host-side bao-cred. The agents AppRole mount is used by nothing else, so
# every token it issues is a Requester sharing the host-agent identity.
requester "host-agent" {
  auth_mount = "agents"
}

grants {
  default_ttl = "1h"
  pending_ttl = "24h"
}

grantable "github-token" {
  path         = "github/token/project-*"
  capabilities = ["read"]
  max_ttl      = "8h"
}

web_push {
  public_key_file       = "/run/secrets/vapid_public_key"
  private_key_file      = "/run/secrets/vapid_private_key"
  subject               = env.VAPID_SUBJECT
  allowed_host_suffixes = [
    "fcm.googleapis.com",
    "updates.push.services.mozilla.com",
    "web.push.apple.com",
    "ntfy.sh",
  ]
}
