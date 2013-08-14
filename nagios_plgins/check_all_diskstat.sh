#!/bin/bash

EXIT_CODE=0
CHK=/usr/lib/nagios/plugins/check_diskstat.sh
WARN=${1:-"200,10000,10000"}
CRIT=${2:-"300,20000,20000"}

for DEVICE in `ls /sys/block`; do
	if [ -L /sys/block/$DEVICE/device ]; then
		DEVNAME=$(echo /dev/$DEVICE | sed 's#!#/#g')
		echo -n "$DEVNAME: "
		OUT=`$CHK -d $DEVICE -w $WARN -c $CRIT`
		STATUS=$?
		if [ "$EXIT_CODE" -le "$STATUS" ]; then
			EXIT_CODE=$STATUS
		fi
		echo -n $OUT|sed "s#=#_$DEVNAME=#g"
		
	fi
done
exit $EXIT_CODE
