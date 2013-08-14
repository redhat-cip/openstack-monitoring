#!/bin/bash

STATE_OK=0
STATE_WARNING=1
STATE_CRITICAL=2
STATE_UNKNOWN=3
STATE_DEPENDENT=4

CONTAINER_NAME=fooContainer
FILE_TO_UPLOAD=etc/services

usage ()
{
    echo "Usage: $0 [OPTIONS]"
    echo " -h               Get help"
    echo " -H <Auth URL>    URL for obtaining an auth token"
    echo " -U <username>    Username to use to get an auth token"
    echo " -T <tenant>      Tenant to use to get an auth token"
    echo " -P <password>    Password to use ro get an auth token"
}

while getopts 'h:H:U:T:P:' OPTION
do
    case $OPTION in
        h)
            usage
            exit 0
            ;;
        H)
            export OS_AUTH_URL=$OPTARG
            ;;
        U)
            export OS_USERNAME=$OPTARG
            ;;
        T)
            export OS_TENANT_NAME=$OPTARG
            ;;
        P)
            export OS_PASSWORD=$OPTARG
            ;;
        *)
            usage
            exit 1
            ;;
    esac
done


if ! which swift >/dev/null 2>&1
then
    echo "python-swiftclient is not installed."
    exit $STATE_UNKNOWN
fi
#set -x

swift_exec()
{
	cmd=$1
	file=$2
	if [ $cmd == "upload" ]; then
		file="/$2"
	fi
	swift --os-auth-url $OS_AUTH_URL -V 2 --os-username $OS_USERNAME --os-password $OS_PASSWORD --os-tenant-name $OS_TENANT_NAME $cmd $CONTAINER_NAME $file >/dev/null 2>&1
	if [ $? -ne 0 ]; then
		echo "Swift $cmd Failed"
		exit $STATE_CRITICAL
	fi
}
swift_exec upload $FILE_TO_UPLOAD
swift_exec list
swift_exec delete $FILE_TO_UPLOAD
swift_exec list 

echo "Swift upload/list/delete OK"
exit $STATE_OK
