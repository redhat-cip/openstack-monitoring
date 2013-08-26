#!/bin/bash
#
# Heat engine monitoring script
#
# Copyright © 2013 eHeatnce <licensing@enovance.com>
#
# Author: Emilien Macchi <emilien.macchi@enovance.com>
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.
#
# Requirement: netstat
#
set -e

STATE_OK=0
STATE_CRITICAL=2
STATE_UNKNOWN=3

usage ()
{
    echo "Usage: $0 [OPTIONS]"
    echo " -h               Get help"
    echo "No parameter : Just run the script"
}

while getopts 'h:H:U:T:P:' OPTION
do
    case $OPTION in
        h)
            usage
            exit 0
            ;;
        *)
            usage
            exit 1
            ;;
    esac
done

if ! which netstat >/dev/null 2>&1
then
    echo "netstat is not installed."
    exit $STATE_UNKNOWN
fi

PID=$(ps -ef | grep heat-engine | grep python | awk {'print$2'} | head -n 1)
AMQP_PORT=$(grep amqp /etc/services|head -n 1|cut -f 1 -d '/'| awk '{print $2'})
if ! KEY=$(netstat -nepta 2>/dev/null | grep $PID 2>/dev/null | grep ":$AMQP_PORT}) || test -z "$PID"
then
    echo "heat-engine is not connected to AMQP."
    exit $STATE_CRITICAL
fi

echo "heat-engine is working."
exit $STATE_OK
