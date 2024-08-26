#!/bin/bash

# Output file
output_file="vlan_info.txt"

# Function to get IP and MAC address for a VLAN
get_vlan_info() {
    local vlan=$1
    local iface="eth0.$vlan"
    
    # Bring up the VLAN interface
    sudo ifup $iface
    
    # Wait for DHCP to assign an IP address
    sleep 5
    
    # Get IP and MAC address
    ip_address=$(ip -4 addr show $iface | grep -oP '(?<=inet\s)\d+(\.\d+){3}')
    mac_address=$(cat /sys/class/net/$iface/address)
    
    # Store the information in the output file
    echo "VLAN $vlan:" >> $output_file
    echo "IP Address: $ip_address" >> $output_file
    echo "MAC Address: $mac_address" >> $output_file
    echo "" >> $output_file
    
    # Bring down the VLAN interface
    sudo ifdown $iface
}

# Clear the output file
echo "VLAN Information:" > $output_file
echo "=================" >> $output_file
echo "" >> $output_file

# VLANs to cycle through
vlans=("1" "10" "20" "30" "40")

# Iterate through each VLAN, get info, and store it
for vlan in "${vlans[@]}"
do
    get_vlan_info $vlan
done
sudo ifup eth0.1
sudo ifup eth0.10
sudo ifup eth0.20
sudo ifup eth0.30
sudo ifup eth0.40
echo "VLAN information collected and stored in $output_file"
