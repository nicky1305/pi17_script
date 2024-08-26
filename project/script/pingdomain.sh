#!/bin/bash

# Define domains
PING_DNS_FPT="210.245.1.253"
PING_24H_COM_VN="24h.com.vn"
PING_DNS_GOOGLE="8.8.8.8"
PING_GATEWAY=$(ip route | grep default | grep eth0 | awk '{print $3}')

json_output="{\"type\":\"ping_domain\",\"name\":\"pi17\",\"data\":["
ping_time() {
    local domain=$1
    local count=$2
    local cmd_output
    local min avg max mdev packet_loss mac_address

    cmd_output=$(ping -c "$count" "$domain")

    if [ $? -ne 0 ]; then
        echo "Failed to ping $domain"
        min="0"
        avg="0"
        max="0"
        mdev="0"
        packet_loss="1.0"
        status="fail"
    else
        if [[ $cmd_output =~ rtt\ min/avg/max/mdev\ =\ ([0-9\.]+)/([0-9\.]+)/([0-9\.]+)/([0-9\.]+)\ ms ]]; then
            min=${BASH_REMATCH[1]}
            avg=${BASH_REMATCH[2]}
            max=${BASH_REMATCH[3]}
            mdev=${BASH_REMATCH[4]}
        fi

        if [[ $cmd_output =~ ([0-9\.]+)\%\ packet\ loss ]]; then
            packet_loss=${BASH_REMATCH[1]}
        fi
    fi

    mac_address=$(arp -n "$domain" | grep -o -E '([[:xdigit:]]{1,2}:){5}[[:xdigit:]]{1,2}')
    if [ -z "$mac_address" ]; then
        mac_address=$(ip neigh | grep "$domain" | awk '{print $5}')
    fi
    if [ -z "$mac_address" ]; then
        mac_address="00:00:00:00:00:00"
    fi

    local status="fail"
    if (( $(echo "$packet_loss == 0" | bc -l)) && [[ $domain == $PING_GATEWAY ]] && (( $(echo "$avg < 1" | bc -l) ))); then
        status="pass"
    elif (( $(echo "$packet_loss < 1.0" | bc -l)) && [[ $domain == $PING_DNS_FPT ]] && (( $(echo "$avg > 2 && $avg < 5" | bc -l) ))); then
        status="pass"
    elif (( $(echo "$packet_loss < 1.0" | bc -l)) && [[ $domain == $PING_DNS_FPT ]] && (( $(echo "$avg > 24 && $avg < 30" | bc -l) ))); then
        status="pass"
    fi

    json_output="${json_output}{\"domain\":\"$domain\",\"min\":\"$min\",\"avg\":\"$avg\",\"max\":\"$max\",\"mdev\":\"$mdev\",\"packet_loss\":\"$packet_loss\",\"mac_address\":\"$mac_address\",\"status\":\"$status\"},"
}

ping_time_auto() {
    local count=5

    ping_time "$PING_DNS_FPT" "$count"
    echo "Incoming ping DNS_FPT completed"
    ping_time "$PING_24H_COM_VN" "$count"
    echo "Incoming ping 24H completed"
    ping_time "$PING_DNS_GOOGLE" "$count"
    echo "Incoming ping DNS_GOOGLE completed"
    ping_time "$PING_GATEWAY" "$count"
    echo "Incoming ping GATEWAY completed"
}

control_switch_ports() {
    local enable_ports=("$@")
    local disable_ports=(0/1 0/2 0/13 0/14 0/15 0/16)

    # Disable all ports first
    for port in "${disable_ports[@]}"; do
        echo "interface eth$port"
        echo "disable"
    done | screen -S switch -p 0 -X stuff "$(printf "\r")"

    # Enable selected ports
    for port in "${enable_ports[@]}"; do
        echo "interface eth$port"
        echo "enable"
    done | screen -S switch -p 0 -X stuff "$(printf "\r")"

    sleep 5
}

# Start screen session for the switch console
screen -dmS switch /dev/ttyUSB0 9600

# Shutdown 0/1 and enable 0/13, then ping test
control_switch_ports 0/13
ping_time_auto

# Shutdown 0/13 and enable 0/14, then ping test
control_switch_ports 0/14
ping_time_auto

# Shutdown 0/14 and enable 0/15, then ping test
control_switch_ports 0/15
ping_time_auto

# Shutdown 0/15 and enable 0/16, then ping test
control_switch_ports 0/16
ping_time_auto

# Finally, shutdown 0/16 and enable 0/1
control_switch_ports 0/1

json_output="${json_output%,}]}"
echo $json_output

# Send the JSON output to Logstash
response=$(curl -s -o /dev/null -w "%{http_code}" -X POST "https://logstash.lab.as18403.net" -H "Content-Type: application/json" -d "$json_output")

Check the response code and print success or failure message
if [ "$response" -eq 200 ]; then
    echo "Data successfully sent to Logstash"
else
    echo "Failed to send data to Logstash, HTTP response code: $response"
fi

# Terminate the screen session
screen -S switch -X quit
