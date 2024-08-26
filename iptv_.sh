#!/bin/bash

# Set default log directory if not provided
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
    sleep 18s
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
        # rm -f "${LOG_DIRECTORY}/grep_results/dataGrepDropping.txt"
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

            if (( $(echo "${seconds#-} < 0.2" | bc -l) )); then
                status="dropped discontinued and failed screen"
            fi

            real_time=$(convert_dts_to_real_time "${dts_values[i]}")

            if ! $first_line; then
                echo ","
            fi

            # echo -n "    {\"decode_time_stamp\": ${dts_values[i]}, \"real_time\": \"$real_time\", \"time_interval\": ${seconds#-}, \"status_frame\": \"$status\" }"
            echo -n "    {\"decode_time_stamp\": ${dts_values[i]}, \"time_interval\": ${seconds#-}, \"status_frame\": \"$status\" }"
            first_line=false
        done

        echo "  ]"
        echo "}"
    } > "$resultDataHandled"

    rm -f "${LOG_DIRECTORY}/grep_results/dataGrepDropping.txt"
    echo "Done saving handled data dropped discontinued to $resultDataHandled"
}

convert_dts_to_real_time() {
    local dts_value=$1
    local CLOCK_FREQUENCY=90000 
    local real_time_secs=$(date +%s)
    local start_time=${START_TIME_SECS:-$real_time_secs}
    
    if [[ "$dts_value" -eq 0 ]]; then
        echo "$(date '+%a %d %b %Y %r %Z')"
        return
    fi
    
    local time_in_seconds=$(echo "scale=2; $dts_value / $CLOCK_FREQUENCY" | bc)
    local real_time_epoch=$(echo "$start_time + $time_in_seconds" | bc)
    local real_time=$(date -d "@$real_time_epoch" '+%a %d %b %Y %r %Z')
    
    echo "$real_time"
}

################
# *** Main *** #
################

# Handle data dropped and discontinued
handleDataDroppedDiscontinued	

# Send the JSON output to Logstash
response=$(curl -s -o /dev/null -w "%{http_code}" -X POST "http://1.52.246.165:5000" -H "Content-Type: application/json" -d @./logs/dts_diffs.json)

# Check the response code and print success or failure message
if [ "$response" -eq 200 ]; then
    echo "IPTV data successfully sent to Logstash"
    rm -rf ../logs
else
    echo "Failed to send IPTV data to Logstash, HTTP response code: $response"
fi
