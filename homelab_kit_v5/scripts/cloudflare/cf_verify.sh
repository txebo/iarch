#!/usr/bin/env bash
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CFG="$DIR/../../config/cf_env.env"
die(){ echo "ERR: $*" >&2; exit 1; }
need(){ command -v "$1" >/dev/null 2>&1 || die "missing tool: $1"; }
need curl; need jq
[ -f "$CFG" ] || die "config not found: $CFG"
set -a; eval "$(sed -E -e 's/[[:space:]]*#.*$//' -e '/^[[:space:]]*$/d' "$CFG" | sed 's/"/\"/g; s/^/export /')"; set +a
: "${CF_ACCOUNT_ID:?missing}"; : "${CF_ZONE_ID:?missing}"; : "${CF_TUNNEL_ID:?missing}"; : "${CF_API_TOKEN:?export CF_API_TOKEN first}"
API="https://api.cloudflare.com/client/v4"; auth=(-H "Authorization: Bearer ${CF_API_TOKEN}")
echo "[tunnel]"; curl -sS "${auth[@]}" "$API/accounts/$CF_ACCOUNT_ID/cfd_tunnel/$CF_TUNNEL_ID" | jq '.result | {id,name,cname,created_at}'
echo "[dns]"; curl -sS "${auth[@]}" "$API/zones/$CF_ZONE_ID/dns_records?type=CNAME" | jq '.result[] | {name,content,proxied}'
echo "[access apps]"; curl -sS "${auth[@]}" "$API/accounts/$CF_ACCOUNT_ID/access/apps" | jq '.result[] | {id,name,domain,session_duration}'
echo "[routes]"; curl -sS "${auth[@]}" "$API/accounts/$CF_ACCOUNT_ID/cfd_tunnel/$CF_TUNNEL_ID/routes" | jq '.result[] | {network,virtual_network_id}'
