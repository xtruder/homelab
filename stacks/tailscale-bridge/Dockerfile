FROM tailscale/tailscale:latest

RUN rm /usr/sbin/iptables && ln -s /usr/sbin/iptables-nft /usr/sbin/iptables && \
    rm /usr/sbin/ip6tables && ln -s /usr/sbin/ip6tables-nft /usr/sbin/ip6tables

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
