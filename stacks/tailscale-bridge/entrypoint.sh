#!/bin/sh
set -e

ip addr add $(wget -qO- --timeout=5 https://icanhazip.com)/32 dev eth0 2>/dev/null || true

if [ -n "$TS_DEST_IP" ]; then
    # work: proxy to target tailnet
    /usr/local/bin/containerboot &

    while [ ! -d /sys/class/net/tailscale0 ]; do sleep 1; done
    sleep 2

    iptables -t nat -A PREROUTING -i eth0 -j DNAT --to-destination ${TS_DEST_IP}
    iptables -t nat -A POSTROUTING -o tailscale0 -j MASQUERADE
    iptables -A FORWARD -i eth0 -o tailscale0 -j ACCEPT
    iptables -A FORWARD -i tailscale0 -o eth0 -m state --state ESTABLISHED,RELATED -j ACCEPT

    MY_IP=$(ip -4 addr show tailscale0 | sed -n 's/.*inet \([0-9.]*\).*/\1/p')
    echo "=== work Ready ==="
    echo "IP: ${MY_IP}"
    echo "Proxying to: ${TS_DEST_IP}"

    wait
else
    # personal: forward to work container
    /usr/local/bin/containerboot &

    while [ ! -d /sys/class/net/tailscale0 ]; do sleep 1; done

    MY_IP=$(ip -4 addr show tailscale0 | sed -n 's/.*inet \([0-9.]*\).*/\1/p')

    iptables -t nat -A PREROUTING -i tailscale0 -j DNAT --to-destination ${PROXY_TARGET}
    iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
    iptables -A FORWARD -i tailscale0 -o eth0 -j ACCEPT
    iptables -A FORWARD -i eth0 -o tailscale0 -m state --state ESTABLISHED,RELATED -j ACCEPT

    echo "=== personal Ready ==="
    echo "IP: ${MY_IP}"
    echo "Forwarding to: ${PROXY_TARGET}"

    wait
fi
