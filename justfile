default:
  @just --list

generate:
  bluebuild generate ./recipes/ucore-server.yml -o Containerfile

build: generate
  bluebuild build ./recipes/ucore-server.yml
