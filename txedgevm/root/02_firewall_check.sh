#!/usr/bin/env bash
set -euo pipefail
sysctl net.ipv4.ip_forward
systemctl status nftables --no-pager || true
nft list ruleset | sed -n '1,120p'
