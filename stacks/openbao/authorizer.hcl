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

# Named Tokens of projects, minted by `bao-cred init` / `bao-cred auth`.
requester "named" {
  token_role = "named-identity"
}

# Agent session tokens, minted by bao-cred from a project's Named Token.
requester "sessions" {
  token_role = "agent-session"
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
  description  = "GitHub App installation token for one project; the name picks the org, repositories and permissions (see permission-sets.json)."
  # Lets agents see every project-* permission set; needs the list stanza in
  # policies/authorizer.hcl.
  discover = "github/permissionsets"
}

grantable "ssh-cert" {
  path         = "ssh/sign/*"
  capabilities = ["update"]
  max_ttl      = "8h"
  description  = "Sign an SSH public key for one node and user: the role name picks both (see ssh-roles.json). Certificates are valid 1h; the Grant only limits how long new ones may be signed."
  # Needs the list stanza for ssh/roles/ in policies/authorizer.hcl.
  discover = "ssh/roles"
}

grantable "git-sign" {
  path         = "transit/sign/git-*"
  capabilities = ["update"]
  max_ttl      = "8h"
  description  = "Sign git commits with one person's transit key (see signing-keys.json); bao-cred-ssh-keygen asks for it when git signs."
  # Needs the list stanza for transit/keys/ in policies/authorizer.hcl.
  discover = "transit/keys"
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
