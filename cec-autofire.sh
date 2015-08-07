#!/bin/bash
#THIS SCRIPT MUST BE RUN AS ROOT
# cec-autofire.sh
# Starts Kodi based on CEC tafic by detecting which source is selected on the TV
# toine512, 07/08/2015
# me@toine512.fr

#Configuration
target_route='40:00'
pipe=/tmp/cec-autofire_fifo

#Check root privileges
if [ "$(id -u)" != '0' ]; then
	logger -s -p daemon.crit -t 'cec-autofire.sh' 'This script must be run as root!'
	exit 77
fi

#FIFO handling
if [[ ! -p $pipe ]]; then
	mkfifo $pipe
fi
trap "rm -f $pipe" EXIT

while true; do
	#Start CEC listener in the background
	logger -p daemon.notice -t 'cec-autofire.sh' 'Starting cec-client listener.'
	cec-client -m -sf $pipe &>/dev/null &
	cecc_pid=$!

	#Waiting for "route change" notification : 0f:80:prev_route:curr_route.
	#In my case the Pi is connected to HDMI 4, as an example
	#when switching from HDMI 1 to HDMI 4 the Sony Bravia KDL-40EX500 broadcasts the following message:
	#>> 0f:80:10:00:40:00
	if grep -E -q "^>> 0f:80:[0-9a-z]{2}:[0-9a-z]{2}:$target_route" $pipe; then
		logger -p daemon.info -t 'cec-autofire.sh' 'Terminating CEC listener.'
		kill -s SIGTERM $cecc_pid
		sleep 1
		logger -p daemon.notice -t 'cec-autofire.sh' 'Launching Kodi! Starting mediacenter service.'
		systemctl start mediacenter
		#Giving some time to Kodi for starting properly before monitoring the process
		sleep 30
	else
		kill -s SIGTERM $cecc_pid
		logger -p daemon.crit -t 'cec-autofire.sh' 'Failure while watching HDMI CEC in order to launch Kodi!'
		exit 1
	fi

	#Kodi IS NOW RUNNING

	#After manual exit, the mediacenter service does not stop
	#We have to do it ourselves when kodi.bin dies
	logger -p daemon.debug -t 'cec-autofire.sh' 'Kodi is now running... :-)'
	while ps cax | grep -q 'kodi.bin'; do
		#This has to be less than the watchdog timeout
		sleep 9
	done
	logger -p daemon.debug -t 'cec-autofire.sh' 'Kodi stopped. Terminating mediacenter service.'
	systemctl stop mediacenter
done
