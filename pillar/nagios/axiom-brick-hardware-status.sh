#!/bin/bash

cd $(dirname $0)
source ./axiom-common.sh

file=/tmp/axiom.brick.hardware.$1

axiom system -list -outputformat xml | \
  grep -v 'TemperatureStatus' | \
  xpath -q -s "" -e '//Brick/*[name()="Name" or contains(name(),"Status")]' | \
  sed -e "s#</[^>]*Status>#\n#g" \
      -e 's/<[^>]*Status>/: /g'  \
      -e 's/<[^>]*>//g' | \
  sort > $file

if test -z "$(cat $file |grep -v ": NORMAL")"; then
  echo "OK - all bricks running"
  STATUS=$STATE_OK
else
  echo "CRITICAL - problems on $(cat $file |grep -v ": NORMAL"|wc -l) bricks :"
  STATUS=$STATE_CRITICAL
fi

cat $file
rm $file
exit $STATUS
