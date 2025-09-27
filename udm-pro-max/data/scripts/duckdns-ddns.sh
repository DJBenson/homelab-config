#!/bin/bash

DUCKDNS_TOKEN=""
WAN1_DOMAIN=""
WAN2_DOMAIN=""

STATE_FILE="/data/duckdns-ddns/duckdns-last_ips.json"
mkdir -p "$(dirname "$STATE_FILE")"

JSON_STATE=$( [[ -f "$STATE_FILE" ]] && cat "$STATE_FILE" || echo "{}" )

get_now() {
    date -Iseconds
}

# Get IPs
IPV4_ppp1=$(ip -4 addr show dev ppp1 | grep -oP '(?<=inet\s)\d+(\.\d+){3}')
IPV4_ETH8=$(ip -4 addr show dev eth8 | grep -oP '(?<=inet\s)\d+(\.\d+){3}')
IPV6_ETH8=$(ip -6 addr show dev eth8 | grep -oP '(?<=inet6\s)[\da-f:]+(?=/)' | grep -v '^fe80' | head -n 1)

update_duckdns() {
    local DOMAIN=$1 IP=$2 TYPE=$3
    local KEY="${DOMAIN}_${TYPE}" TIMESTAMP=$(get_now)
    [[ -z "$IP" ]] && echo "❌ Skipping $KEY: no IP" && return

    LAST_IP=$(echo "$JSON_STATE" | jq -r --arg key "$KEY" '.[$key].ip // empty')
    [[ "$IP" == "$LAST_IP" ]] && echo "⏭️  No change for $KEY ($IP)" && return

    PARAM="ip"
    [[ "$TYPE" == "AAAA" ]] && PARAM="ipv6"

    RESPONSE=$(curl -s "https://www.duckdns.org/update?domains=$DOMAIN&token=$DUCKDNS_TOKEN&$PARAM=$IP")
    if [[ "$RESPONSE" == "OK" ]]; then
        echo "✅ Updated $KEY to $IP"
        JSON_STATE=$(echo "$JSON_STATE" | jq --arg key "$KEY" --arg ip "$IP" --arg time "$TIMESTAMP" \
            '.[$key].ip = $ip | .[$key].last_update = $time')
    else
        echo "❌ Failed to update $KEY: $RESPONSE"
    fi
}

update_duckdns "$WAN1_DOMAIN" "$IPV4_ETH8" "A"
update_duckdns "$WAN1_DOMAIN" "$IPV6_ETH8" "AAAA"
update_duckdns "$WAN2_DOMAIN" "$IPV4_ppp1" "A"

# Save run time
JSON_STATE=$(echo "$JSON_STATE" | jq --arg now "$(get_now)" '.last_run = $now')
echo "$JSON_STATE" > "$STATE_FILE"
