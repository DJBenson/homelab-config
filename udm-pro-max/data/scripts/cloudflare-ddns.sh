#!/bin/bash

CF_API_TOKEN=""
ZONE_ID=""

WAN1_NAME=""
WAN2_NAME=""

CF_HEADERS=(-H "Authorization: Bearer $CF_API_TOKEN" -H "Content-Type: application/json")
STATE_FILE="/data/cloudflare-ddns/cloudflare-last_ips.json"
mkdir -p "$(dirname "$STATE_FILE")"

JSON_STATE=$( [[ -f "$STATE_FILE" ]] && cat "$STATE_FILE" || echo "{}" )

get_now() {
    date -Iseconds
}

# Get IPs
IPV4_ETH8=$(ip -4 addr show dev eth8 | grep -oP '(?<=inet\s)\d+(\.\d+){3}')
IPV6_ETH8=$(ip -6 addr show dev eth8 | grep -oP '(?<=inet6\s)[\da-f:]+(?=/)' | grep -v '^fe80' | head -n 1)
IPV4_ppp1=$(ip -4 addr show dev ppp1 | grep -oP '(?<=inet\s)\d+(\.\d+){3}')

get_record_id() {
    curl -s -X GET "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records?type=$1&name=$2" "${CF_HEADERS[@]}" |
    grep -oP '"id":"\K[^"]+'
}

update_dns() {
    local TYPE=$1 IP=$2 NAME=$3 RECORD_ID=$4
    local KEY="${NAME}_${TYPE}" TIMESTAMP=$(get_now)
    [[ -z "$IP" || -z "$RECORD_ID" ]] && echo "❌ Skipping $KEY: missing IP or ID" && return

    LAST_IP=$(echo "$JSON_STATE" | jq -r --arg key "$KEY" '.[$key].ip // empty')
    [[ "$IP" == "$LAST_IP" ]] && echo "⏭️  No change for $KEY ($IP)" && return

    RESPONSE=$(curl -s -X PUT "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records/$RECORD_ID" \
        "${CF_HEADERS[@]}" \
        --data "{\"type\":\"$TYPE\",\"name\":\"$NAME\",\"content\":\"$IP\",\"ttl\":300,\"proxied\":true}")

    if echo "$RESPONSE" | grep -q '"success":true'; then
        echo "✅ Updated $KEY to $IP"
        JSON_STATE=$(echo "$JSON_STATE" | jq --arg key "$KEY" --arg ip "$IP" --arg time "$TIMESTAMP" \
            '.[$key].ip = $ip | .[$key].last_update = $time')
    else
        echo "❌ Failed to update $KEY:"
        echo "$RESPONSE"
    fi
}

# Run updates
update_dns "A" "$IPV4_ETH8" "$WAN1_NAME" "$(get_record_id A $WAN1_NAME)"
update_dns "AAAA" "$IPV6_ETH8" "$WAN1_NAME" "$(get_record_id AAAA $WAN1_NAME)"
update_dns "A" "$IPV4_ppp1" "$WAN2_NAME" "$(get_record_id A $WAN2_NAME)"

# Save run time
JSON_STATE=$(echo "$JSON_STATE" | jq --arg now "$(get_now)" '.last_run = $now')
echo "$JSON_STATE" > "$STATE_FILE"
