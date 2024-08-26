#!/bin/bash

echo "This program ----- TEST RASPI CHECK IPTV -----"
                     
export LOG_DIRECTORY="/home/test1/workspace"
FILENAME="${MYSELF/.sh/}raspi-check-iptv.log"
LOG_FILE="${LOG_DIRECTORY}${FILENAME}"
rm -f $LOG_FILE 1>/dev/null 2>&1
exec > >(tee -a "$LOG_FILE") 2>&1

#################################################################################
#
# --- owner: thuanLN2-cpelab
#
# (tooltest automation: quality modem wifi using raspberryPi execute)
#
#################################################################################

# supported languages
MSG_EN=1      # english	(default)
MSG_UNDEFINED=0
MSG_EN[$MSG_UNDEFINED]="INFO_0: Undefined message. Pls inform the author %1"
MSG_MISSING_COMMANDS=1
MSG_EN[$MSG_MISSING_COMMANDS]="INFO_1: Following commands are missing and reduce the value of the analysis result: %1 %2 %3 %4 %5 %6 %7 %8 %9 %10"
MSG_STARTING_DATA_COLLECTION=2
MSG_EN[$MSG_STARTING_DATA_COLLECTION]="INFO_2: Starting collection of data and network analysis. This may take some time ..."
MSG_PING_OK=3
MSG_EN[$MSG_PING_OK]="INFO_3: Ping of %1 successful"
MSG_PING_FAILED=4
MSG_EN[$MSG_PING_FAILED]="INFO_4: Ping of %1 failed"
MSG_CHECK_OUTPUT=5
MSG_EN[$MSG_CHECK_OUTPUT]="INFO_5: Check logfile %1"
MSG_ENABLE_RUN_WITH_MISSING_PACKAGES=6
MSG_EN[$MSG_ENABLE_RUN_WITH_MISSING_PACKAGES]="INFO_6: Some required packages are not installed. Option -m will ignore them and run the program with reduced analysis capabilities"
MSG_APT_HINT=7
MSG_EN[$MSG_APT_HINT]="INFO_7: 'sudo apt-get update; sudo apt-get install %1' will install the missing network tools if there exist a working wired network connection"
MSG_USAGE=8
MSG_EN[$MSG_USAGE]="INFO_8: Aufruf: $MYSELF [-e | -s SSID | -h | -m | -g | -l LANGUAGE]\nParameter:\n-e : Test wired connection only\n-h : help\n-m : Ignore missing networking packages\n-s : Test wired and wireless connection\n-g : Messages in English only\n-l : Write messages in selected language if supported (de|en)"
declare -A MSG_HEADER=( ['I']="---" ['W']="!!!" ['E']="???" )

	
# Create message and substitute parameters
function getMessageText() {
   local msg
   local p
   local i
   local s

   if (( $NO_XLATION )); then
      msg=${MSG_EN[$2]};            
   else

	  if [[ $1 != "L" ]]; then
		LANG_SUFF=$(echo $1 | tr '[:lower:]' '[:upper:]')
	  else
		LANG_EXT=$(echo $LANG | tr '[:lower:]' '[:upper:]')
		LANG_SUFF=${LANG_EXT:0:2}
	  fi

      msgVar="MSG_${LANG_SUFF}"

      if [[ -n ${!msgVar} ]]; then
         msgVar="$msgVar[$2]"
         msg=${!msgVar}
         if [[ -z $msg ]]; then		                 
			msg=${MSG_EN[$2]};      	    	          
		 fi
      else
		  msg=${MSG_EN[$2]};      	      	              
      fi
   fi

   for (( i=3; $i <= $#; i++ )); do            		
      p="${!i}"
      let s=$i-2
      s="%$s"
      msg=$(echo $msg | sed 's!'$s'!'$p'!')			
   done
   msg=$(echo $msg | perl -p -e "s/%[0-9]+//g" 2>/dev/null)     
   local msgNum=$(cut -f 1 -d ':' <<< $msg)
   local severity=${msgNum: -1}
   local msgHeader=${MSG_HEADER[$severity]}
   echo "$msgHeader $msg"
}


function writeToConsole() {  
   local msg
   if [[ -z $DESIRED_LANGUAGE ]]; then		
		msg=$(getMessageText L $@)
   else
		msg=$(getMessageText $DESIRED_LANGUAGE $@)
   fi
		
   echo -e $msg
}

function detectMods() {

	MODS="PING DIG IP EGREP AWK IFCONFIG IWCONFIG IWLIST SED LSUSB GREP PERL ROUTE ARP"  

	for mod in $MODS; do
		lwr=$(echo $mod | tr '[:upper:]' '[:lower:]')
		p=$(find {/sbin,/usr/bin,/usr/sbin,/bin} -name $lwr | head -n 1)
		eval "$mod=\"${p}\""
		if [[ -z $p ]]; then
			if [ -z "$MODS_MISSING_LIST" ]; then
				MODS_MISSING_LIST=$lwr
			else
				MODS_MISSING_LIST="$MODS_MISSING_LIST $lwr"
			fi
			MODS_MISSING=1
		fi
	done

	declare -A REQUIRED_PACKET_MAP=([iwconfig]=wireless-tools [iwlist]=wireless-tools [lsusb]=usbutils [dig]=dnsutils)
	declare -A USED_PACKET_MAP=()

	for p in $MODS_MISSING_LIST; do
		needed_package=${REQUIRED_PACKET_MAP[$p]}
		if [ -z "$required_packages" ]; then		
			required_packages=$needed_package
		else
			if [ ! ${USED_PACKET_MAP[$needed_package]+_}  ]; then			
				required_packages="$required_packages $needed_package"
			fi
		fi
		eval USED_PACKET_MAP[$needed_package]="1"							
	done

	if (( $MODS_MISSING )); then
		writeToConsole $MSG_MISSING_COMMANDS "$MODS_MISSING_LIST"
		writeToConsole $MSG_APT_HINT "$required_packages"
		if (( ! $SKIP_MODULES )); then
			writeToConsole $MSG_ENABLE_RUN_WITH_MISSING_PACKAGES
			exit 127
		fi
	fi

}


function usage() {
   echo "$MYSELF $VERSION (CVS Rev $CVS_REVISION_ONLY - $CVS_DATE_ONLY)" 
   echo "$LICENSE"
   writeToConsole $MSG_USAGE
   exit 0
}


###################################
# Print function check log iptv
###################################

function rawDataDroppedDiscontinued() {
    ffmpeg -fflags +discardcorrupt -i udp://@225.1.1.155:30120 -f null /dev/null > "${LOG_FILE}" 2>&1 &
    PID=$!
    sleep 40s
    kill $PID

    if [ $? -eq 0 ]; then
        echo "ffmpeg process terminated successfully."
    else
        echo "Failed to terminate ffmpeg process."
    fi
}

function handleDataDroppedDiscontinued() {
    resultDataHandled="${LOG_DIRECTORY}dts_diffs.json"
    rm -f "$resultDataHandled"
    declare -a dts_values

    # Call the raw data handling function
    rawDataDroppedDiscontinued 

    # Extract lines containing "dropping it"
    grep "dropping it" "$LOG_FILE" > "${LOG_DIRECTORY}/dataGrepDropping.txt" 2>&1
    count=$(grep -c "dropping it" "${LOG_DIRECTORY}/dataGrepDropping.txt")

    # If no packets are dropped, output a specific message in the JSON file
    if [ "$count" -eq 0 ]; then
        echo "No packets are dropped during the stream. Writing default JSON output."

        {
            echo "{"
            echo "  \"detailPacketsFail\": ["
            echo "    {\"message\": \"No packets are dropped during the stream\" }"
            echo "  ]"
            echo "}"
        } > "$resultDataHandled"
        
        echo "Done saving handled data dropped discontinued to $resultDataHandled"
        rm -f "${LOG_DIRECTORY}/dataGrepDropping.txt"
        return
    fi

    # Prepare DTS values array from the grep results
    {
        echo "{"
        if [ "$count" -le 4 ]; then
            echo "  \"detailPacketsPass\": ["
        else
            echo "  \"detailPacketsFail\": ["
        fi

        first_line=true
        while IFS= read -r line; do
            if echo "$line" | grep -q "NOPTS"; then
                # Extract the timestamp and directly add the NOPTS entry
                dts=$(echo "$line" | grep -oP 'dts = \K\d+')
               # timestamp=$(date -d @$((${dts}/90000)) +"%a %d %b %Y %I:%M:%S %p %Z")
                if ! $first_line; then
                    echo ","
                fi
                echo -n "    {\"Exception packet\": \"Packet corrupt no dts\", \"dts\": \"NOPTS\", \"status_frame\": \"dropped discontinued and failed screen\" }"
                first_line=false
            else
                dts=$(echo "$line" | grep -oP 'dts = \K\d+')
                dts_values+=("$dts")
            fi
        done < "${LOG_DIRECTORY}/dataGrepDropping.txt"

        for ((i = 1; i < ${#dts_values[@]}; i++)); do
            diff=$(( ${dts_values[i]} - ${dts_values[i-1]} ))
            seconds=$(printf "%.3f" $(echo "scale=3; $diff / 90000" | bc))
            status="dropped discontinued"

            if (( $(echo "${seconds#-} < 0.8" | bc -l) )); then
                status="dropped discontinued and failed screen"
            fi

            # Convert DTS to real time (Implement this function based on your requirements)
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

    rm -f "${LOG_DIRECTORY}/dataGrepDropping.txt"
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

detectMods
# Do your job
if (( $TEST )); then									
	args=$(echo $@ | sed 's/-t//')							
	testMyself "$args"
else
	handleDataDroppedDiscontinued	
fi