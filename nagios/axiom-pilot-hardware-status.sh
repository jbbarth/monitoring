#!/bin/bash

cd $(dirname $0)
source ./axiom-common.sh

file=/tmp/axiom.pilot.hardware.$1

axiom system -list -outputformat xml | \
  grep -v 'TemperatureStatus' | \
  grep -v 'ConfigurationServerStatus' | \
  sed -e 's#<Pilot>#<Pilot><Name>Pilot</Name>#' \
      -e 's#<PilotControlUnitName>#<PilotControlUnitName>CU #g' \
      -e 's#PilotControlUnitName#Name#g' | \
  xpath -q -s "" -e '//Pilot//*[name()="Name" or contains(name(),"Status")]' | \
  sed -e "s#</[^>]*Status>#\n#g" \
      -e 's/<[^>]*Status>/: /g'  \
      -e 's/<[^>]*>//g' > $file

if test -z "$(cat $file |grep -v ": NORMAL")"; then
  echo "OK - pilot running"
  STATUS=$STATE_OK
else
  echo "CRITICAL - problem on pilot :"
  STATUS=$STATE_CRITICAL
fi

cat $file
rm $file
exit $STATUS
