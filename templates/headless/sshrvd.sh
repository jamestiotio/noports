#!/bin/bash
# allow machine to bring up network
sleep 10
USER=$(whoami) 
export USER
while true
do
# $1 = atSign
# $2 = FQDN/IP
~/sshnp/sshrvd -a "$1" -i "$2"
sleep 10
done