# Policy of openbao-git-proxy's own token (github.com/xtruder/openbao-git-proxy).
# It reads the git-proxy mount's repositories and upstream credentials and
# renews itself; access is decided by capabilities-self with each agent's
# own token, never with this one. Created without the default policy.
path "git-proxy/repos" {
  capabilities = ["list"]
}

path "git-proxy/repo/*" {
  capabilities = ["read"]
}

# Returns upstream passwords: no other policy should allow read here.
path "git-proxy/credential/*" {
  capabilities = ["read"]
}

path "auth/token/renew-self" {
  capabilities = ["update"]
}
