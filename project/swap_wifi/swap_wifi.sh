#!/bin/bash

# Configuration
INTERFACE="wlan0"
SSID_5GHz="ANNK4 - AX3000CV2 - 5GHz"
SSID_2_4GHz="ANNK4 - AX3000CV2 - 2.4GHz"
LOGFILE="/var/log/wifi_switch.log"

# Function to connect to a specified SSID
connect_to_ssid() {
    local ssid=$1
    echo "$(date): Attempting to connect to SSID: $ssid" >> $LOGFILE
    sudo wpa_cli -i $INTERFACE disconnect
    sudo wpa_cli -i $INTERFACE scan
    sudo wpa_cli -i $INTERFACE scan_results
    sudo wpa_cli -i $INTERFACE select_network $(sudo wpa_cli -i $INTERFACE list_networks | grep "$ssid" | awk '{print $1}')
    sudo wpa_cli -i $INTERFACE reconnect
}

# Function to get the current SSID
get_current_ssid() {
    iwgetid -r
}

# Main logic
while true; do
    current_ssid=$(get_current_ssid)
    if [[ "$current_ssid" != "$SSID_5GHz" && "$current_ssid" != "$SSID_2_4GHz" ]]; then
        echo "$(date): Not connected to the correct SSID, attempting to connect." >> $LOGFILE
        # First try connecting to 5GHz
        connect_to_ssid "$SSID_5GHz"
        sleep 10
        # Check connection
        if [[ "$(get_current_ssid)" != "$SSID_5GHz" ]]; then
            # If not connected to 5GHz, try 2.4GHz
            connect_to_ssid "$SSID_2_4GHz"
        fi
    fi
    sleep 30
done
