#!/bin/bash

# UniFi WAN Monitor via MQTT Discovery for Home Assistant

# --- Configuration ---
UDM_IP=""
UDM_USER=""
UDM_PASS=""

MQTT_HOST=""
MQTT_PORT=1883
MQTT_USER=""
MQTT_PASS=""
MQTT_BASE="homeassistant/binary_sensor"

COOKIE_FILE="/tmp/unifi_cookie.txt"
LOGIN_URL="https://${UDM_IP}/api/auth/login"
API_URL="https://${UDM_IP}/proxy/network/api/s/default/stat/device"

# --- Login to UniFi ---
curl -sk -c "$COOKIE_FILE" -X POST "$LOGIN_URL" \
  -H "Content-Type: application/json" \
  -d "{\"username\":\"$UDM_USER\", \"password\":\"$UDM_PASS\"}" > /dev/null

CSRF_TOKEN=$(grep csrf_token "$COOKIE_FILE" | awk '{print $7}')
RESPONSE=$(curl -sk -b "$COOKIE_FILE" -H "x-csrf-token: $CSRF_TOKEN" "$API_URL")

# --- Publish WAN Info via MQTT ---
publish_wan_mqtt() {
    local IFACE="$1"
    local SENSOR_ID="unifi_${IFACE}_status"
    local SENSOR_NAME=""
    if [ "$IFACE" = "wan" ]; then
        SENSOR_NAME="WAN 1 Connection"
    elif [ "$IFACE" = "wan2" ]; then
        SENSOR_NAME="WAN 2 Connection"
    else
        SENSOR_NAME="WAN Connection"
    fi

    local DEVICE_NAME="UniFi WAN"
    local DEVICE_ID="unifi_udm"
    local DISCOVERY_TOPIC="$MQTT_BASE/$SENSOR_ID/config"
    local STATE_TOPIC="$MQTT_BASE/$SENSOR_ID/state"
    local ATTR_TOPIC="$MQTT_BASE/$SENSOR_ID/attributes"

    # Extract port data
    DATA=$(echo "$RESPONSE" | jq -r --arg IFACE "$IFACE" '
      .data[] | select(.type=="udm") | .port_table[]
      | select(.network_name==$IFACE)')

    IS_UP=$(echo "$DATA" | jq -r '.up')
    STATE="OFF"
    [ "$IS_UP" == "true" ] && STATE="ON"

    IP=$(echo "$DATA" | jq -r '.ip // "none"')
    SPEED=$(echo "$DATA" | jq -r '.speed // 0')
    MEDIA=$(echo "$DATA" | jq -r '.media // "unknown"')
    MAC=$(echo "$DATA" | jq -r '.mac // "unknown"')
    TX=$(echo "$DATA" | jq -r '.tx_bytes // 0')
    RX=$(echo "$DATA" | jq -r '.rx_bytes // 0')
    TX_RATE=$(echo "$DATA" | jq -r '."tx_bytes-r" // 0')
    RX_RATE=$(echo "$DATA" | jq -r '."rx_bytes-r" // 0')

    TX_HR=$(numfmt --to=iec --suffix=B "$TX")
    RX_HR=$(numfmt --to=iec --suffix=B "$RX")
    TX_RATE_HR=$(awk "BEGIN {printf \"%.2f Mbit/s\", $TX_RATE * 8 / 1000000}")
    RX_RATE_HR=$(awk "BEGIN {printf \"%.2f Mbit/s\", $RX_RATE * 8 / 1000000}")

    # Publish MQTT discovery config
    mosquitto_pub -h "$MQTT_HOST" -p "$MQTT_PORT" -u "$MQTT_USER" -P "$MQTT_PASS" \
        -t "$DISCOVERY_TOPIC" \
        -m "{
            \"name\": \"$SENSOR_NAME\",
            \"unique_id\": \"$SENSOR_ID\",
            \"state_topic\": \"$STATE_TOPIC\",
            \"json_attributes_topic\": \"$ATTR_TOPIC\",
            \"device_class\": \"connectivity\",
            \"payload_on\": \"ON\",
            \"payload_off\": \"OFF\",
            \"device\": {
                \"identifiers\": [\"$DEVICE_ID\"],
                \"name\": \"$DEVICE_NAME\",
                \"model\": \"UDM Pro Max\",
                \"manufacturer\": \"Ubiquiti\"
            }
        }"
    sleep 2

    # Publish sensor state
    mosquitto_pub -h "$MQTT_HOST" -p "$MQTT_PORT" -u "$MQTT_USER" -P "$MQTT_PASS" \
        -t "$STATE_TOPIC" -m "$STATE"

    # Publish sensor attributes
    mosquitto_pub -h "$MQTT_HOST" -p "$MQTT_PORT" -u "$MQTT_USER" -P "$MQTT_PASS" \
        -t "$ATTR_TOPIC" -m "{
            \"ip\": \"$IP\",
            \"mac\": \"$MAC\",
            \"speed_mbps\": $SPEED,
            \"media\": \"$MEDIA\",
            \"tx_bytes\": $TX,
            \"rx_bytes\": $RX,
            \"tx_human\": \"$TX_HR\",
            \"rx_human\": \"$RX_HR\",
            \"tx_rate_bps\": $TX_RATE,
            \"rx_rate_bps\": $RX_RATE,
            \"tx_rate_human\": \"$TX_RATE_HR\",
            \"rx_rate_human\": \"$RX_RATE_HR\"
        }"
}

# Run for both WAN interfaces
publish_wan_mqtt "wan"
publish_wan_mqtt "wan2"

    
