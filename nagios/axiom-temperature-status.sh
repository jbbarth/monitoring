#!/bin/bash

cd $(dirname $0)
source ./axiom-common.sh

file=/tmp/axiom.temperature.$1

axiom system -list -outputformat xml | \
  xpath -q -s "" -e '//*[TemperatureStatus]/*[name()="Name" or name()="TemperatureStatus"]' | \
  sed -e "s#</TemperatureStatus>#\n#g" \
      -e 's/<TemperatureStatus>/: /g'  \
      -e 's/<[^>]*>//g' | \
  sort > $file

if test -z "$(cat $file |grep -v ": NORMAL")"; then
  echo "OK - temperatures are ok"
  STATUS=$STATE_OK
else
  echo "CRITICAL - temperature problems:"
  STATUS=$STATE_CRITICAL
fi

cat $file
rm $file
exit $STATUS
