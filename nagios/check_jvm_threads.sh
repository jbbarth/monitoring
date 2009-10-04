#!/bin/bash

DEBUG=0
PROGNAME=`basename $0`
PROGPATH=`dirname $0`

. $PROGPATH/../utils.sh

SWALK=$(which snmpwalk);

if [ "$#" -lt "1" ]; then
    echo "USAGE: $0 <host> [community-string] [warning-threads,critical-threads]"
    exit 3;
fi

if [ ! -n "$SWALK" ]; then
    echo "No snmpwalk found!";
    exit 3;
fi

debug() {
    if [ "$DEBUG" == "1" ]; then
        echo "DEBUG: $1"
    fi
}
swalk() {
    #-r specified number of snmpwalk retries
    res=$($SWALK -v2c -r 0 -c $community $host $1 2>/dev/null)
    ret=$?
    if [ "$ret" == "0" ]; then
        echo $res | awk '{print $4}'
        return 0
    fi
    exit 1
}
exit_problem() {
    echo "Threads(UNKNOWN): snmpwalk error or timeout !"
    exit $STATE_UNKNOWN
}

#parameters
host=$1
community=$([ -z $2 ] && echo "public" || echo $2)
p_threads=$([ -z $3 ] && echo "75,100" || echo $3)
w_threads=${p_threads/,*}
c_threads=${p_threads/*,}
debug "parameters:"
debug "  server   : $host"
debug "  community: $community"
debug "  threads  : warning: $w_threads, critical: $c_threads (max values for number of threads launched by this JVM)"

#useful oid's
oid_threads="1.3.6.1.4.1.42.2.145.3.163.1.1.3.1";

threads=$(swalk $oid_threads) || exit_problem
debug "threads: $threads"

if [ "$threads" -gt "$c_threads" ]; then
    echo "Threads(CRITICAL): $threads (>$c_threads)"
    exit $STATE_CRITICAL
elif [ "$threads" -gt "$w_threads" ]; then
    echo "Threads(WARNING): $threads (>$w_threads)"
    exit $STATE_WARNING
else
    echo "Threads(OK): $threads"
    exit $STATE_OK
fi
