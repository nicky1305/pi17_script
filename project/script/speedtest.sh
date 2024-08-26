#!/bin/bash

PING_GATEWAY=$(ip route | grep default | grep eth0 | awk '{print $3}')

# SSH to the AP to get the MAC address
GATEWAY_MAC=$(sshpass -p 'Admin@123456' ssh -o StrictHostKeyChecking=no root@$PING_GATEWAY "ifconfig | grep eth0 | awk '{print \$5}'")
echo $GATEWAY_MAC
# Extract the last two octets for SSID
SSID_SUFFIX=$(echo $GATEWAY_MAC | awk -F: '{print $5 $6}')
SSID2_4="FPT Telecom-$SSID_SUFFIX 2.4GHz"
SSID5="FPT Telecom-$SSID_SUFFIX 5GHz"
# Print retrieved values
echo "GATEWAY MAC: $GATEWAY_MAC"
echo "SSID 2.4GHz: $SSID2_4"
echo "SSID 5GHz: $SSID5"

# Create the result directory if it doesn't exist
mkdir -p ./result

# Initialize the JSON file
{
echo "{"
echo "\"type\": \"speed_test\","
echo "\"name\": \"pi17\","
echo "\"AP\": \"$GATEWAY_MAC\","
echo "\"data\": []"
echo "}"
} > "./result/speedtest.json"

# Function to append results to the JSON file
append_to_json() {
    local interface="$1"
    local upload="$2"
    local download="$3"
    local packetloss="$4"

    jq --arg interface "$interface" --arg upload "$upload" --arg download "$download" --arg packetloss "$packetloss" \
       '.data += [{"interface": $interface, "Upload": $upload, "Download": $download, "Packetloss": $packetloss}]' \
       ./result/speedtest.json > ./result/speedtest_tmp.json
    mv ./result/speedtest_tmp.json ./result/speedtest.json
}

# Function to run the speedtest and get results
run_speedtest() {
    result=$(speedtest -s 2515 --format=json)
    download=$(echo "$result" | jq -r '.download.bandwidth')
    upload=$(echo "$result" | jq -r '.upload.bandwidth')
    packetloss=$(echo "$result" | jq -r '.packetLoss')
    echo "$download $upload $packetloss"
}

# Turn off all interfaces
sudo ifconfig wlan0 down
sudo ifconfig eth0 down

# Test Ethernet
sudo ifconfig eth0 up
read eth_download eth_upload eth_packetloss <<< $(run_speedtest)
append_to_json "eth0" "$eth_upload" "$eth_download" "$eth_packetloss"
sudo ifconfig eth0 down

# Test 5GHz Wi-Fi
sudo ifconfig wlan0 up
sudo iw wlan0 connect "$SSID5" key 0:12345678  # Connect to 5GHz band (example frequency: 5180 MHz)
read wifi5_download wifi5_upload wifi5_packetloss <<< $(run_speedtest)
append_to_json "5GHz" "$wifi5_upload" "$wifi5_download" "$wifi5_packetloss"

# Test 2.4GHz Wi-Fi
sudo iw wlan0 connect "$SSID2_4" key 0:12345678  # Connect to 2.4GHz band (example frequency: 2412 MHz)
read wifi24_download wifi24_upload wifi24_packetloss <<< $(run_speedtest)
append_to_json "2.4GHz" "$wifi24_upload" "$wifi24_download" "$wifi24_packetloss"

# Connect back to 5GHz
sudo iw wlan0 connect "$SSID5" key 0:12345678  # Connect back to 5GHz band
sudo ifconfig eth0 up
sleep 10

# Send the JSON output to Logstash
response=$(curl -s -o /dev/null -w "%{http_code}" -X POST "https://logstash.lab.as18403.net" -H "Content-Type: application/json" -d @./result/speedtest.json)

# Check the response code and print success or failure message
if [ "$response" -eq 200 ]; then
    echo "speedtest data successfully sent to Logstash"
    rm -rf ../result
else
    echo "Failed to send speedtest data to Logstash, HTTP response code: $response"
fi
