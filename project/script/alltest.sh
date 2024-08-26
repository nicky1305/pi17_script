#!/bin/bash

export LOG_DIRECTORY="./combined_logs"
# export SCRIPT_1="./speedtest.sh"
export SCRIPT_2="./pingdomain.sh"
export SCRIPT_3="./iptv_.sh"
export COMBINED_LOG="${LOG_DIRECTORY}/combined_output.log"

mkdir -p "$LOG_DIRECTORY"

if [ ! -f "$COMBINED_LOG" ]; then
    touch "$COMBINED_LOG"
fi

add_separator() {
    echo "," >> "$COMBINED_LOG"
}

# bash "$SCRIPT_1" >> "$COMBINED_LOG"
# add_separator

bash "$SCRIPT_2" >> "$COMBINED_LOG"
add_separator

bash "$SCRIPT_3" >> "$COMBINED_LOG"
add_separator

response=$(curl -s -o /dev/null -w "%{http_code}" -X POST "https://logstash.lab.as18403.net" -H "Content-Type: application/json" -d @"$COMBINED_LOG")
if [ "$response" -eq 200 ]; then
    echo "Combined log data successfully sent to Logstash"
    rm -rf "$LOG_DIRECTORY"
else
    echo "Failed to send combined log data to Logstash, HTTP response code: $response"
fi
