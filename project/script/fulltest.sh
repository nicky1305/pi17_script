#!/bin/bash

#=================#
# Define Parameter#
#=================#
# Define domains
PING_DNS_FPT="210.245.1.253"
PING_24H_COM_VN="24h.com.vn"
PING_DNS_GOOGLE="8.8.8.8"
PING_GATEWAY=$(ip route | grep default | grep wlan0 | awk '{print $3}')

# Define IPTV Param
LOG_DIRECTORY=${LOG_DIRECTORY:-"./logs"}
FILENAME="${MYSELF/.sh/}raspi-check-iptv.log"
LOG_FILE="${LOG_DIRECTORY}/${FILENAME}"

# Create necessary directories
mkdir -p "$LOG_DIRECTORY"

# Remove existing log file
rm -f "$LOG_FILE" 1>/dev/null 2>&1

###################################
# Print function check log iptv
###################################

function rawDataDroppedDiscontinued() {
    # Ensure the directory exists for ffmpeg logs
    mkdir -p "${LOG_DIRECTORY}/ffmpeg_logs"
    LOG_FILE="${LOG_DIRECTORY}/ffmpeg_logs/${FILENAME}"

    ffmpeg -fflags +discardcorrupt -i udp://@225.1.1.190:30120 -f null /dev/null > "${LOG_FILE}" 2>&1 &
    PID=$!
    sleep 36s
    kill $PID

    if [ $? -eq 0 ]; then
        echo "ffmpeg process terminated successfully."
    else
        echo "Failed to terminate ffmpeg process."
    fi
}

function handleDataDroppedDiscontinued() {
    resultDataHandled="${LOG_DIRECTORY}/dts_diffs.json"
    rm -f "$resultDataHandled"
    declare -a dts_values

    # Call the raw data handling function
    rawDataDroppedDiscontinued 

    # Create a directory for grep results if it doesn't exist
    mkdir -p "${LOG_DIRECTORY}/grep_results"
    grep "dropping it" "$LOG_FILE" > "${LOG_DIRECTORY}/grep_results/dataGrepDropping.txt" 2>&1
    count=$(grep -c "dropping it" "${LOG_DIRECTORY}/grep_results/dataGrepDropping.txt")

    # If no packets are dropped, output a specific message in the JSON file
    if [ "$count" -eq 0 ]; then
        echo "No packets are dropped during the stream. Writing default JSON output."

        {
            echo "{"
            echo "  \"type\": \"iptv\","
            echo "  \"name\": \"pi17\","
            echo "  \"URL\": \"udp://@225.1.1.190:30120\","
            echo "  \"detailPacketsPass\": ["
            echo "    {\"message\": \"No packets are dropped during the stream\" }"
            echo "  ]"
            echo "}"
        } > "$resultDataHandled"
        
        echo "Done saving handled data dropped discontinued to $resultDataHandled"
        rm -f "${LOG_DIRECTORY}/grep_results/dataGrepDropping.txt"
        return
    fi

    # Prepare DTS values array from the grep results
    {
        echo "{"
        if [ "$count" -le 4 ]; then
            echo "  \"type\": \"iptv\","
            echo "  \"name\": \"pi17\","
            echo "  \"URL\": \"udp://@225.1.1.190:30120\","
            echo "  \"detailPacketsPass\": ["
        else
            echo "  \"type\": \"iptv\","
            echo "  \"name\": \"pi17\","
            echo "  \"URL\": \"udp://@225.1.1.190:30120\","
            echo "  \"detailPacketsFail\": ["
        fi

        first_line=true
        while IFS= read -r line; do
            if echo "$line" | grep -q "NOPTS"; then
                if ! $first_line; then
                    echo ","
                fi
                echo -n "    {\"Exception packet\": \"Packet corrupt no dts\", \"dts\": \"NOPTS\", \"status_frame\": \"dropped discontinued and failed screen\" }"
                first_line=false
            else
                dts=$(echo "$line" | grep -oP 'dts = \K\d+')
                dts_values+=("$dts")
            fi
        done < "${LOG_DIRECTORY}/grep_results/dataGrepDropping.txt"

        for ((i = 1; i < ${#dts_values[@]}; i++)); do
            diff=$(( ${dts_values[i]} - ${dts_values[i-1]} ))
            seconds=$(printf "%.3f" $(echo "scale=3; $diff / 90000" | bc))
            status="dropped discontinued"

            if (( $(echo "${seconds#-} < 0.8" | bc -l) )); then
                status="dropped discontinued and failed screen"
            fi

            real_time=$(convert_dts_to_real_time "${dts_values[i]}")

            if ! $first_line; then
                echo ","
            fi

            echo -n "    {\"decode_time_stamp\": ${dts_values[i]}, \"real_time\": \"$real_time\", \"time_interval\": ${seconds#-}, \"status_frame\": \"$status\" }"
            first_line=false
        done

        echo "  ]"
        echo "}"
    } > "$resultDataHandled"

    rm -f "${LOG_DIRECTORY}/grep_results/dataGrepDropping.txt"
    echo "Done saving handled data dropped discontinued to $resultDataHandled"
}

CLOCK_FREQUENCY=90000
# Function to convert DTS to real time
convert_dts_to_real_time() {
  local dts_value=$1
  local real_time_secs=$(date +%s)
  local start_time=${START_TIME_SECS:-$real_time_secs}
  local time_in_seconds=$(echo "scale=2; $dts_value / $CLOCK_FREQUENCY" | bc)
  local real_time_epoch=$(echo "$start_time + $time_in_seconds" | bc)
  local real_time=$(date -d "@$real_time_epoch" '+%a %d %b %Y %r %Z')
  echo "$real_time"
}

# Define json format
json_output="{\"name\":\"pi17\",\"type\":\"fulltest\",\"testcase\":["

#=================#
# Define Function #
#=================#
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
    json_output="${json_output%,}{\"sort\":\"pingtest\",\"APs\":[},"
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


#=============#
# Main Script #
#=============#

ping_time_auto
json_output="${json_output%,}},"

#======================================#
# Response Error Post data to Logstash #
#======================================#

# Check the response code and print success or failure message
if [ "$response" -eq 200 ]; then
    echo "Data successfully sent to Logstash"
else
    echo "Failed to send data to Logstash, HTTP response code: $response"
fi