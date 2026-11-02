# keep in sync with host tailscaled version, --verify-clients queries its LocalAPI
ARG TAILSCALE_VERSION=v1.104.4

FROM docker.io/library/golang:1.27.3-alpine AS build
ARG TAILSCALE_VERSION
RUN CGO_ENABLED=0 go install tailscale.com/cmd/derper@${TAILSCALE_VERSION}

FROM docker.io/library/alpine:3.24
RUN apk add --no-cache ca-certificates openssl
COPY --from=build /go/bin/derper /usr/local/bin/derper
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
