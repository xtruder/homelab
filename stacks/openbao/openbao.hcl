ui = true
cluster_addr = "https://openbao:8201"

seal "static" {
  current_key_id = "homelab-static-seal-v1"
  current_key    = "file:///run/secrets/openbao_static_seal_key"
}

storage "raft" {
  path    = "/openbao/data"
  node_id = "openbao-1"
}

listener "tcp" {
  address         = "0.0.0.0:8200"
  cluster_address = "0.0.0.0:8201"
  tls_disable     = true
}

plugin_directory = "/openbao/plugins"
