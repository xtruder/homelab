ARG HERMES_AGENT_IMAGE=docker.io/nousresearch/hermes-agent:v2026.8.19
FROM ${HERMES_AGENT_IMAGE}

ARG CUA_DRIVER_VERSION=cua-driver-rs-v0.20.0

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        at-spi2-core \
        chromium \
        dbus-x11 \
        libxi6 \
        openssl \
        weston \
        x11-utils \
        xwayland \
    && rm -rf /var/lib/apt/lists/* \
    && CUA_DRIVER_RS_VERSION="${CUA_DRIVER_VERSION}" \
        /bin/bash -c "$(curl -fsSL https://cua.ai/driver/install.sh)" \
    && install -m 0755 /root/.local/bin/cua-driver /usr/local/bin/cua-driver \
    && rm -rf /root/.cua-driver /root/.local/bin/cua-driver

COPY desktop/hermes-desktop /usr/local/bin/hermes-desktop
COPY desktop/hermes-chromium /usr/local/bin/hermes-chromium
COPY desktop/weston.ini /etc/xdg/weston/weston.ini
COPY desktop/s6-run /etc/s6-overlay/s6-rc.d/hermes-desktop/run

RUN chmod 0755 \
        /usr/local/bin/hermes-desktop \
        /usr/local/bin/hermes-chromium \
        /etc/s6-overlay/s6-rc.d/hermes-desktop/run \
    && mkdir -p \
        /etc/s6-overlay/s6-rc.d/hermes-desktop/dependencies.d \
        /etc/s6-overlay/s6-rc.d/user/contents.d \
    && touch \
        /etc/s6-overlay/s6-rc.d/hermes-desktop/dependencies.d/base \
        /etc/s6-overlay/s6-rc.d/user/contents.d/hermes-desktop \
    && printf 'longrun\n' > /etc/s6-overlay/s6-rc.d/hermes-desktop/type

ENV DBUS_SESSION_BUS_ADDRESS=unix:path=/run/hermes-desktop/dbus \
    DISPLAY=:0 \
    HERMES_CUA_DRIVER_CMD=/usr/local/bin/cua-driver \
    NO_AT_BRIDGE=0 \
    XDG_RUNTIME_DIR=/run/hermes-desktop/runtime \
    XDG_SESSION_TYPE=x11
