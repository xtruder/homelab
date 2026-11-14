server {
  listen_address = "0.0.0.0:8080"
}

openbao {
  address    = "http://openbao:8200"
  token_file = "/run/secrets/openbao_git_proxy_token"
  mount      = "git-proxy"
}
