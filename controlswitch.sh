#!/bin/bash

# Define variables
USER="ubnt"
HOST="192.168.100.191"
PASSWORD="ubnt"
ENABLE_PASSWORD="ubnt"
INTERFACE1="0/16"
INTERFACE2="0/15"

# Execute the commands via SSH
ssh -tt -oHostKeyAlgorithms=+ssh-dss $USER@$HOST << EOF
$PASSWORD 
enable
$ENABLE_PASSWORD
config
interface $INTERFACE1
no shutdown
interface $INTERFACE2
shutdown
end
write memory
y
exit
EOF
