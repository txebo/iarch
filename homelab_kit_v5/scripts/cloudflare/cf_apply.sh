#!/usr/bin/env bash
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CFG="$DIR/../../config/cf_env.env"
die(){ echo "ERR: $*" >&2; exit 1; }
need(){ command -v "$1" >/dev/null 2>&1 || die "missing tool: $1"; }
need curl; need jq
[ -f "$CFG" ] || die "config not found: $CFG"
set -a; eval "$(sed -E -e 's/[[:space:]]*#.*$//' -e '/^[[:space:]]*$/d' "$CFG" | sed 's/"/\"/g; s/^/export /')"; set +a
: "${CF_ACCOUNT_ID:?missing}"; : "${CF_ZONE_ID:?missing}"; : "${CF_ZONE:?missing}"; : "${CF_TUNNEL_ID:?missing}"; : "${CF_TUNNEL_NAME:?missing}"; : "${CF_VNET_NAME:?missing}"; : "${CF_ROUTE_CIDR:?missing}"; : "${CF_ACCESS_EMAILS:?missing}"; : "${CF_ACCESS_SESSION:?missing}"; : "${HOST_STASH:?missing}"; : "${HOST_DOWNLOADS:?missing}"; : "${ORIGIN_STASH:?missing}"; : "${ORIGIN_DOWNLOADS:?missing}"; : "${CF_API_TOKEN:?export CF_API_TOKEN first}"
API="https://api.cloudflare.com/client/v4"; auth=(-H "Authorization: Bearer ${CF_API_TOKEN}")
echo "[*] fetch tunnel cname..."
tunnel=$(curl -sS "${auth[@]}" "$API/accounts/$CF_ACCOUNT_ID/cfd_tunnel/$CF_TUNNEL_ID")
cname=$(echo "$tunnel" | jq -r '.result.cname'); [ -n "$cname" ] || die "could not get tunnel cname"
echo "[*] ensure DNS CNAME records..."
ensure_cname(){ local host="$1"; rec=$(curl -sS "${auth[@]}" "$API/zones/$CF_ZONE_ID/dns_records?type=CNAME&name=$host"); id=$(echo "$rec" | jq -r '.result[0].id // empty'); if [ -n "$id" ]; then
  curl -sS -X PUT "${auth[@]}" -H "Content-Type: application/json" -d "{"type":"CNAME","name":"$host","content":"$cname","proxied":true}" "$API/zones/$CF_ZONE_ID/dns_records/$id" >/dev/null
else
  curl -sS -X POST "${auth[@]}" -H "Content-Type: application/json" -d "{"type":"CNAME","name":"$host","content":"$cname","proxied":true}" "$API/zones/$CF_ZONE_ID/dns_records" >/dev/null
fi; echo "    ok: $host -> $cname"; }
ensure_cname "$HOST_STASH"; ensure_cname "$HOST_DOWNLOADS"
echo "[*] ensure Access apps and policy..."
ensure_access(){ local host="$1"; app_json=$(jq -n --arg name "$host" --arg dom "$host" --arg dur "$CF_ACCESS_SESSION" '{name:$name, domain:$dom, session_duration:$dur, type:"self_hosted"}'); existing=$(curl -sS "${auth[@]}" "$API/accounts/$CF_ACCOUNT_ID/access/apps?domain=$host"); app_id=$(echo "$existing" | jq -r '.result[0].id // empty'); if [ -n "$app_id" ]; then
  curl -sS -X PUT "${auth[@]}" -H "Content-Type: application/json" -d "$app_json" "$API/accounts/$CF_ACCOUNT_ID/access/apps/$app_id" >/dev/null
else
  app_id=$(curl -sS -X POST "${auth[@]}" -H "Content-Type: application/json" -d "$app_json" "$API/accounts/$CF_ACCOUNT_ID/access/apps" | jq -r '.result.id')
fi
emails_csv="$CF_ACCESS_EMAILS"; cond=$(jq -n --argjson addrs "$(printf '%s' "$emails_csv" | jq -R 'split(",")')" '{decision:"allow", include:[{email:{email: $addrs}}]}')
pol=$(curl -sS "${auth[@]}" "$API/accounts/$CF_ACCOUNT_ID/access/apps/$app_id/policies"); pol_id=$(echo "$pol" | jq -r '.result[0].id // empty'); if [ -n "$pol_id" ]; then
  curl -sS -X PUT "${auth[@]}" -H "Content-Type: application/json" -d "$cond" "$API/accounts/$CF_ACCOUNT_ID/access/apps/$app_id/policies/$pol_id" >/dev/null
else
  curl -sS -X POST "${auth[@]}" -H "Content-Type: application/json" -d "$cond" "$API/accounts/$CF_ACCOUNT_ID/access/apps/$app_id/policies" >/dev/null
fi; echo "    ok: access app+policy for $host"; }
ensure_access "$HOST_STASH"; ensure_access "$HOST_DOWNLOADS"
echo "[*] ensure private route via vnet..."
vnets=$(curl -sS "${auth[@]}" "$API/accounts/$CF_ACCOUNT_ID/zt_virtual_networks"); vnet_id=$(echo "$vnets" | jq -r --arg n "$CF_VNET_NAME" '.result[] | select(.name==$n) | .id' | head -n1); [ -n "$vnet_id" ] || die "vnet not found: $CF_VNET_NAME"
curl -sS -X POST "${auth[@]}" -H "Content-Type: application/json" -d "{"network":"$CF_ROUTE_CIDR","virtual_network_id":"$vnet_id"}" "$API/accounts/$CF_ACCOUNT_ID/cfd_tunnel/$CF_TUNNEL_ID/routes" >/dev/null || true
echo "done."
