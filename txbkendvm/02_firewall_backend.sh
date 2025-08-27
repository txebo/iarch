#!/usr/bin/env bash
set -euo pipefail

# Optional: pass ports as first arg, default "9999,8081"
ALLOWED_PORTS="${1:-9999,8081}"

cat >/etc/nftables.conf <<EOF
#!/usr/bin/env nft -f
flush ruleset

define EDGE_IP = 10.99.64.2
define ALLOWED = {${ALLOWED_PORTS}}

table inet filter {
  chains {
    input {
      type filter hook input priority 0; policy drop;
      iifname lo accept
      ct state established,related accept
      meta l4proto icmp accept
      meta l4proto ipv6-icmp accept

      # SSH only from EDGE
      tcp dport 22 ip saddr \$EDGE_IP accept

      # Backend services only from EDGE
      tcp dport \$ALLOWED ip saddr \$EDGE_IP accept

      counter drop
    }
    forward { type filter hook forward priority 0; policy drop; }
    output  { type filter hook output  priority 0; policy accept; }
  }
}
EOF

systemctl enable --now nftables
nft list ruleset | sed -n '1,120p' || true
