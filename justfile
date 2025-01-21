butane_img := "quay.io/coreos/butane:release"
butane_cmd := "podman run --rm --interactive --security-opt label=disable --volume ${PWD}:/pwd --workdir /pwd " + butane_img

default:
  @just --list

generate:
  bluebuild generate ./recipes/ucore-server.yml -o Containerfile

build: generate
  bluebuild build ./recipes/ucore-server.yml

ignite-jarvis:
  {{butane_cmd}} --strict --pretty ignition/jarvis.bu > ignition/jarvis.ign
