#!/bin/bash

# Define Gateway
GATEWAY=$(ip route | grep default | grep eth0 | awk '{print $3}')

# Define Base IP
BASE_IP=$(echo $GATEWAY | sed 's/\.[0-9]*$//')

# Define Switch
SWITCH=$(sshpass -p 'Admin@123456' ssh -o StrictHostKeyChecking=no root@$GATEWAY "ip neigh | grep f0:9f:c2:0a:1b:63 | grep $BASE_IP | awk '{print \$1}'")

##########################################################################################################################

# Enable eth0 and wlan0 interfaces
sudo ifconfig eth0 up
sudo ifconfig wlan0 up

# Get the current IP address of eth0
CURRENT_IP=$(ip -4 addr show eth0 | grep -oP '(?<=inet\s)\d+(\.\d+){3}')

# Check if we got an IP address
if [ -z "$CURRENT_IP" ]; then
    echo "No IP address found for eth0."
    exit 1
fi

# Extract the base IP (without the last octet)
BASE_IP=$(echo $CURRENT_IP | sed 's/\.[0-9]*$//')

# Set the static IP addresses
ETH0_STATIC_IP="${BASE_IP}.253"
WLAN0_STATIC_IP="${BASE_IP}.254"

echo "sudo ifconfig eth0 $ETH0_STATIC_IP netmask 255.255.255.0"
echo "sudo ifconfig wlan0 $WLAN0_STATIC_IP netmask 255.255.255.0"

# Display the new IP addresses
echo "eth0 is set to static IP: $ETH0_STATIC_IP"
echo "wlan0 is set to static IP: $WLAN0_STATIC_IP"

echo "Gateway is $GATEWAY"
echo "BASE_IP is $BASE_IP"
echo "SWITCH is $SWITCH"