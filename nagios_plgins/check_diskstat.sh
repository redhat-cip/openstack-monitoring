#!/bin/bash

DISK=
WARNING=
CRITICAL=

E_OK=0
E_WARNING=1
E_CRITICAL=2
E_UNKNOWN=3


show_help() {
	echo "$0 -d DEVICE -w tps,read,write -c tps,read,write | -h"
	echo
	echo "This plug-in is used to be alerted when maximum hard drive io/s or sectors read|write/s is reached"
	echo
	echo "  -d DEVICE            DEVICE must be without /dev (ex: -d sda)"
	echo "  -w/c TPS,READ,WRITE  TPS means transfer per seconds (aka IO/s)"
	echo "                       READ and WRITE are in sectors per seconds"
	echo
	echo " example: $0 -d sda -w 200,100000,100000 -c 300,200000,200000"
}

# process args
while [ ! -z "$1" ]; do 
	case $1 in
		-d)	shift; DISK=$1 ;;
		-w)	shift; WARNING=$1 ;;
		-c)	shift; CRITICAL=$1 ;;
		-h)	show_help; exit 1 ;;
	esac
	shift
done

# generate HISTFILE filename
HISTFILE=/var/tmp/check_diskstat.$DISK

# check input parameters so we can continu !
sanitize() {
	# check device name
	if [ -z "$DISK" ]; then
		echo "Need device name, ex: sda"
		exit $E_UNKNOWN
	fi

	# check thresholds
	if [ -z "$WARNING" ]; then
		echo "Need warning threshold"
		exit $E_UNKNOWN
	fi
	if [ -z "$CRITICAL" ]; then
		echo "Need critical threshold"
		exit $E_UNKNOWN
	fi
	
	# 
	if [ -z "$WARN_TPS" -o -z "$WARN_READ" -o -z "$WARN_WRITE" ]; then
		echo "Need 3 values for warning threshold (tps,read,write)"
		exit $E_UNKNOWN
	fi
	if [ -z "$CRIT_TPS" -o -z "$CRIT_READ" -o -z "$CRIT_WRITE" ]; then
		echo "Need 3 values for critical threshold (tps,read,write)"
		exit $E_UNKNOWN
	fi
		

}

readdiskstat() {
	if [ ! -f "/sys/block/$1/stat" ]; then
		return $E_UNKNOWN
	fi

	cat /sys/block/$1/stat
}

readhistdiskstat() {
	[ -f $HISTFILE ] && cat $HISTFILE
}

# process thresholds
WARN_TPS=$(echo $WARNING | cut -d , -f 1)
WARN_READ=$(echo $WARNING | cut -d , -f 2)
WARN_WRITE=$(echo $WARNING | cut -d , -f 3)
CRIT_TPS=$(echo $CRITICAL | cut -d , -f 1)
CRIT_READ=$(echo $CRITICAL | cut -d , -f 2)
CRIT_WRITE=$(echo $CRITICAL | cut -d , -f 3)
# check args
sanitize


NEWDISKSTAT=$(readdiskstat $DISK)
if [ $? -eq $E_UNKNOWN ]; then
	echo "Cannot read disk stats, check your /sys filesystem for $DISK"
	exit $E_UNKNOWN
fi

if [ ! -f $HISTFILE ]; then
	echo $NEWDISKSTAT >$HISTFILE
	echo "UNKNOWN - Initial buffer creation..." 
	exit $E_UNKNOWN
fi

OLDDISKSTAT=$(readhistdiskstat)
if [ $? -ne 0 ]; then
	echo "Cannot read histfile $HISTFILE..."
	exit $E_UNKNOWN
fi
OLDDISKSTAT_TIME=$(stat $HISTFILE | grep Modify | sed 's/^.*: \(.*\)$/\1/')
OLDDISKSTAT_EPOCH=$(date -d "$OLDDISKSTAT_TIME" +%s)
NEWDISKSTAT_EPOCH=$(date +%s)

echo $NEWDISKSTAT >$HISTFILE
# now we have old and current stat; 
# let compare it
OLD_SECTORS_READ=$(echo $OLDDISKSTAT | awk '{print $3}')
NEW_SECTORS_READ=$(echo $NEWDISKSTAT | awk '{print $3}')
OLD_READ=$(echo $OLDDISKSTAT | awk '{print $1}')
NEW_READ=$(echo $NEWDISKSTAT | awk '{print $1}')
OLD_WRITE=$(echo $OLDDISKSTAT | awk '{print $5}')
NEW_WRITE=$(echo $NEWDISKSTAT | awk '{print $5}')

OLD_SECTORS_WRITTEN=$(echo $OLDDISKSTAT | awk '{print $7}')
NEW_SECTORS_WRITTEN=$(echo $NEWDISKSTAT | awk '{print $7}')

# kernel handles sectors by 512bytes
# http://www.mjmwired.net/kernel/Documentation/block/stat.txt
SECTORBYTESIZE=512

let "SECTORS_READ = $NEW_SECTORS_READ - $OLD_SECTORS_READ"
let "SECTORS_WRITE = $NEW_SECTORS_WRITTEN - $OLD_SECTORS_WRITTEN"
let "TIME = $NEWDISKSTAT_EPOCH - $OLDDISKSTAT_EPOCH"
let "BYTES_READ_PER_SEC = $SECTORS_READ * $SECTORBYTESIZE / $TIME"
let "BYTES_WRITTEN_PER_SEC = $SECTORS_WRITE * $SECTORBYTESIZE / $TIME"
let "TPS=($NEW_READ - $OLD_READ + $NEW_WRITE - $OLD_WRITE) / $TIME"

let "KBYTES_READ_PER_SEC = $BYTES_READ_PER_SEC / 1024"
let "KBYTES_WRITTEN_PER_SEC = $BYTES_WRITTEN_PER_SEC / 1024"

OUTPUT=""
EXITCODE=$E_OK
# check TPS
if [ $TPS -gt $WARN_TPS ]; then
	if [ $TPS -gt $CRIT_TPS ]; then
		OUTPUT="critical IO/s (>$CRIT_TPS), "
		EXITCODE=$E_CRITICAL
	else
		OUTPUT="warning IO/s (>$WARN_TPS), "
		EXITCODE=$E_WARNING
	fi
fi
# check read
if [ $BYTES_READ_PER_SEC -gt $WARN_READ ]; then
	if [ $BYTES_READ_PER_SEC -gt $CRIT_READ ]; then
		OUTPUT="${OUTPUT}critical read sectors/s (>$CRIT_READ), "
		EXITCODE=$E_CRITICAL
	else
		OUTPUT="${OUTPUT}warning read sectors/s (>$WARN_READ), "
		[ "$EXITCODE" -lt $E_CRITICAL ] && EXITCODE=$E_WARNING
	fi
fi

# check write
if [ $BYTES_WRITTEN_PER_SEC -gt $WARN_WRITE ]; then
	if [ $BYTES_WRITTEN_PER_SEC -gt $CRIT_WRITE ]; then
		OUTPUT="${OUTPUT}critical write sectors/s (>$CRIT_WRITE), "
		EXITCODE=$E_CRITICAL
	else
		OUTPUT="${OUTPUT}warning write sectors/s (>$WARN_WRITE), " 
		[ "$EXITCODE" -lt $E_CRITICAL ] && EXITCODE=$E_WARNING
	fi
fi


echo "${OUTPUT}summary: $TPS io/s, read $SECTORS_READ sectors (${KBYTES_READ_PER_SEC}kB/s), write $SECTORS_WRITE sectors (${KBYTES_WRITTEN_PER_SEC}kB/s) in $TIME seconds // "
#echo "${OUTPUT}summary: $TPS io/s, read $SECTORS_READ sectors (${KBYTES_READ_PER_SEC}kB/s), write $SECTORS_WRITE sectors (${KBYTES_WRITTEN_PER_SEC}kB/s) in $TIME seconds | tps=${TPS}io/s;;; read=${BYTES_READ_PER_SEC}b/s;;; write=${BYTES_WRITTEN_PER_SEC}b/s;;; "
exit $EXITCODE

