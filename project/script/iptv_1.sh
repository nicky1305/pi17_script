#!/bin/bash

# Set default log directory if not provided
LOG_DIRECTORY=${LOG_DIRECTORY:-"./logs"}
FILENAME="${MYSELF/.sh/}raspi-check-iptv.log"
LOG_FILE="${LOG_DIRECTORY}/${FILENAME}"

# Define SSID
INTERFACE="wlan0"
SSID_5GHz="ANNK4 - AX3000CV2 - 5GHz"
SSID_2_4GHz="ANNK4 - AX3000CV2 - 2.4GHz"
LOGFILE="./test_log/wifi_switch.log"

# Create necessary directories
mkdir -p "$LOG_DIRECTORY"

# Remove existing log file
rm -f "$LOG_FILE" 1>/dev/null 2>&1

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

# Function to check log iptv
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

function handleDataDroppedDiscontinued5ghz() {
    resultDataHandled="${LOG_DIRECTORY}/dts_diffs_5ghz.json"
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
            echo "  \"SSID\": \"$SSID_5GHz\","
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
        echo "  \"SSID\": \"$SSID_5GHz\","
        echo "  \"detailPacketsPass\": ["
        else
            echo "  \"type\": \"iptv\","
            echo "  \"name\": \"pi17\","
            echo "  \"SSID\": \"$SSID_5GHz\","
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

            echo -n "    {\"decode_time_stamp\": ${dts_values[i]}, \"real_time\": \"$real_time\",  \"time_interval\": ${seconds#-}, \"status_frame\": \"$status\" }"
            first_line=false
        done

        echo "  ]"
        echo "}"
    } > "$resultDataHandled"

    rm -f "${LOG_DIRECTORY}/grep_results/dataGrepDropping.txt"
    echo "Done saving handled data dropped discontinued to $resultDataHandled"
}

function handleDataDroppedDiscontinued24ghz() {
    resultDataHandled="${LOG_DIRECTORY}/dts_diffs_2_4ghz.json"
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
            echo "  \"SSID\": \"$SSID_2_4GHz\","
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
        echo "  \"SSID\": \"$SSID_2_4GHz\","
        echo "  \"detailPacketsPass\": ["
        else
            echo "  \"type\": \"iptv\","
            echo "  \"name\": \"pi17\","
            echo "  \"SSID\": \"$SSID_2_4GHz\","
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

            echo -n "    {\"decode_time_stamp\": ${dts_values[i]}, \"real_time\": \"$real_time\",  \"time_interval\": ${seconds#-}, \"status_frame\": \"$status\" }"
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

################
# *** Main *** #
################

TEST=0
# Sample function detectMods, you should define this based on your actual implementation
detectMods() {
echo "detectMods function not implemented."
}

# Do your job
if (( $TEST )); then
        args=$(echo $@ | sed 's/-t//')
        testMyself "$args"
else
        handleDataDroppedDiscontinued5ghz   
fi

connect_to_ssid "$SSID_2_4GHz"

# Sample function detectMods, you should define this based on your actual implementation
detectMods() {
echo "detectMods function not implemented."
}

# Do your job
if (( $TEST )); then
        args=$(echo $@ | sed 's/-t//')
        testMyself "$args"
else
        handleDataDroppedDiscontinued5ghz   
fi

connect_to_ssid "$SSID_5GHz"

# Bring down the eth0 interface after the test is finished
#sudo ip link set eth0 down
#if [ $? -ne 0 ]; then
#    echo "Failed to bring down eth0."
#fi

# Send the JSON output to Logstash
response=$(curl -s -o /dev/null -w "%{http_code}" -X POST "http://192.168.36.183:5044" -H "Content-Type: application/json" -d @./logs/dts_diffs.json)
# Check the response code and print success or failure message
if [ "$response" -eq 200 ]; then
    echo "IPTV data successfully sent to Logstash"
    rm -rf ../logs
else
    echo "Failed to send IPTV data to Logstash, HTTP response code: $response"
fi
