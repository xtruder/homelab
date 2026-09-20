server {
  listen_address   = "0.0.0.0:8080"
  public_origin    = "https://baoauthz.${env.DOMAIN_NAME}"
  insecure_cookies = false
  static_directory = ""
}

storage {
  database_path       = "/var/lib/openbao-authorizer/app.db"
  encryption_key_file = "/run/secrets/authorizer_encryption_key"
}

openbao {
  address            = "http://openbao:8200"
  namespace          = ""
  ca_file            = ""
  scanner_token_file = "/run/secrets/openbao_scanner_token"
  approver_policy    = "openbao-authorizer-approver"
}

scanner {
  interval    = "5s"
  concurrency = 8
}

requests {
  expose_data = false
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

approval_context "github-token" {
  match_path = "github/token/{name}"
  read_path  = "github/permissionset/{name}"
}
