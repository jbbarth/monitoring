#!/bin/bash

DEBUG=0
PROGNAME=`basename $0`
PROGPATH=`dirname $0`

. $PROGPATH/../utils.sh

SWALK=$(which snmpwalk);

if [ "$#" -lt "1" ]; then
    echo "USAGE: $0 <host> [community-string] [warning-heap,critical-heap]"
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
    echo "Heap(UNKNOWN): snmpwalk error or timeout !"
    exit $STATE_UNKNOWN
}

#parameters
host=$1
community=$([ -z $2 ] && echo "public" || echo $2)
p_heapsize=$([ -z $3 ] && echo "80,90" || echo $3)
w_heapsize=${p_heapsize/,*}
c_heapsize=${p_heapsize/*,}
debug "parameters:"
debug "  server   : $host"
debug "  community: $community"
debug "  heapsize : warning: $w_heapsize%, critical: $c_heapsize% (max values for heap_used/heap_max ratio)"

#useful oid's
oid_heap_used="1.3.6.1.4.1.42.2.145.3.163.1.1.2.11";
oid_heap_committed="1.3.6.1.4.1.42.2.145.3.163.1.1.2.12"
oid_heap_max="1.3.6.1.4.1.42.2.145.3.163.1.1.2.13";
oid_non_heap_used="1.3.6.1.4.1.42.2.145.3.163.1.1.2.21";
oid_non_heap_committed="1.3.6.1.4.1.42.2.145.3.163.1.1.2.22"
oid_non_heap_max="1.3.6.1.4.1.42.2.145.3.163.1.1.2.23";

heap_used=$(swalk $oid_heap_used) || exit_problem
debug "heap_used: $heap_used"
#heap_committed=$(swalk $oid_heap_committed) || exit_problem
#debug "heap_committed: $heap_committed"
heap_max=$(swalk $oid_heap_max) || exit_problem
debug "heap_max: $heap_max"

#see: http://java.sun.com/javase/6/docs/api/java/lang/management/MemoryUsage.html
#and: http://java.sun.com/j2se/1.5.0/docs/guide/management/jconsole.html
heap_used_over_max=$(echo "100 * $heap_used / $heap_max" | bc)
debug "heap_used_over_max: $heap_used_over_max"
heap_used_mb=$[ $heap_used / 1024 / 1024 ]
heap_max_mb=$[ $heap_max / 1024 / 1024 ]
perfdata="heap_used=$[ $heap_used / 1024 / 1024 ]MB;;;0;"

if [ "$heap_used_over_max" -gt "$c_heapsize" ]; then
    echo "Heap_used(CRITICAL): $heap_used_over_max% (${heap_used_mb}MB/${heap_max_mb}MB) (>$c_heapsize%) | $perfdata"
    exit $STATE_CRITICAL
elif [ "$heap_used_over_max" -gt "$w_heapsize" ]; then
    echo "Heap_used(WARNING): $heap_used_over_max% (${heap_used_mb}MB/${heap_max_mb}MB) (>$w_heapsize%) | $perfdata"
    exit $STATE_WARNING
else
    echo "Heap_used(OK): $heap_used_over_max% | $perfdata"
    exit $STATE_OK
fi
