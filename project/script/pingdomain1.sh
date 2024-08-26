#!/bin/bash

# Kill any existing 'switch' sessions
screen -S switch -X quit

# Generate a unique session name using the current timestamp
SESSION_NAME="switch_$(date +%s)"

# Start screen session for the switch console
screen -dmS "$SESSION_NAME" /dev/ttyUSB0 115200

# Define domains
PING_DNS_FPT="210.245.1.253"
PING_24H_COM_VN="24h.com.vn"
PING_DNS_GOOGLE="8.8.8.8"
PING_GATEWAY=$(ip route | grep default | grep eth0 | awk '{print $3}')

# Define json format
json_output="{\"type\":\"pingtest\",\"name\":\"pi17\",\"APs\":["

# Function to send commands to the switch
send_command_to_switch() {
    local command="$1"
    screen -S "$SESSION_NAME" -p 0 -X stuff "$command$(printf '\r')"
}

# Define ping function
ping_domain() {
    local domain=$1
    local count=$2
    local cmd_output
    local min avg max mdev packet_loss

    cmd_output=$(ping -c "$count" "$domain")

    if [ $? -ne 0 ]; then
        echo "Failed to ping $domain"
        min="0"
        avg="0"
        max="0"
        mdev="0"
        packet_loss="1.0"
        status="fail"
    fi

    if [[ $cmd_output =~ rtt\ min/avg/max/mdev\ =\ ([0-9\.]+)/([0-9\.]+)/([0-9\.]+)/([0-9\.]+)\ ms ]]; then
        min=${BASH_REMATCH[1]}
        avg=${BASH_REMATCH[2]}
        max=${BASH_REMATCH[3]}
        mdev=${BASH_REMATCH[4]}
    fi

    if [[ $cmd_output =~ ([0-9\.]+)\%\ packet\ loss ]]; then
        packet_loss=${BASH_REMATCH[1]}
    fi

    local status="fail"
    if (( $(echo "$packet_loss == 0") )); then
        status="pass"
    fi

    json_output="${json_output}{\"domain\":\"$domain\",\"min\":\"$min\",\"avg\":\"$avg\",\"max\":\"$max\",\"mdev\":\"$mdev\",\"packet_loss\":\"$packet_loss\",\"status\":\"$status\"},"
}

ping_time_auto() {
    local packets=5
    IP_GATEWAY=$(ip route | grep default | grep eth0 | awk '{print $3}')
    mac_address=$(arp -n "$IP_GATEWAY" | grep -o -E '([[:xdigit:]]{1,2}:){5}[[:xdigit:]]{1,2}')
    if [ -z "$mac_address" ]; then
        mac_address=$(ip neigh | grep "$IP_GATEWAY" | awk '{print $5}')
    fi
    if [ -z "$mac_address" ]; then
        mac_address="00:00:00:00:00:00"
    fi
    json_output="${json_output}{\"AP\":\"$mac_address\", \"data\":["
    ping_domain "$PING_DNS_FPT" "$packets"
    echo "Incoming ping DNS_FPT completed"
    ping_domain "$PING_24H_COM_VN" "$packets"
    echo "Incoming ping 24H completed"
    ping_domain "$PING_DNS_GOOGLE" "$packets"
    echo "Incoming ping DNS_GOOGLE completed"
    ping_domain "$PING_GATEWAY" "$packets"
    echo "Incoming ping GATEWAY completed"
    json_output="${json_output%,}]},"
}

control_switch_ports() {
    local enable_ports=("$@")
    local disable_ports=(0/1 0/2 0/13 0/14 0/15 0/16)

    # Start switch configuration mode
    send_command_to_switch "admin"
    send_command_to_switch "admin"
    send_command_to_switch "enable"
    send_command_to_switch "configuration"

    # Disable all ports first
    for port in "${disable_ports[@]}"; do
        echo "Disabling interface eth$port"
        send_command_to_switch "interface 0/$port"
        send_command_to_switch "shutdown"
    done

    # Enable selected ports
    for port in "${enable_ports[@]}"; do
        echo "Enabling interface eth$port"
        send_command_to_switch "interface 0/$port"
        send_command_to_switch "no shutdown"
    done

    sleep 5
}

# Initialize switch and ping tests
control_switch_ports 0/1

control_switch_ports 0/13
ping_time_auto

control_switch_ports 0/14
ping_time_auto

control_switch_ports 0/15
ping_time_auto

control_switch_ports 0/16
ping_time_auto

control_switch_ports 0/1
json_output="${json_output%,}]}"
echo $json_output | jq .

# Send the JSON output to Logstash
response=$(curl -s -o /dev/null -w "%{http_code}" -X POST "http://1.52.246.165:5000" -H "Content-Type: application/json" -d "$json_output")
echo "Response code: $response"
echo "Response body:"
cat response.txt

# Check the response code and print success or failure message
if [ "$response" -eq 200 ]; then
    echo "Data successfully sent to Logstash"
else
    echo "Failed to send data to Logstash, HTTP response code: $response"
fi

# Terminate the screen session
screen -S switch -X quit