#!/bin/bash
set -e

cd $(dirname $0)

source /usr/lib/nagios/plugins/utils.sh

export PDS_USER=${PDS_USER:-nagios}
export PDS_PASSWORD=${PDS_PASSWORD:-nagios}
export PDS_HOST=${PDS_DEVICE:-$1}

function axiom_connect() {
  export PDS_KEY=$(./axiomcli login -force -returnKey | head -n 1)
  if echo $PDS_KEY |grep -v ":" >/dev/null; then
    #invalid key!
    echo "Unable to connect to $PDS_HOST"
    echo $PDS_KEY
    exit $STATE_UNKNOWN
  fi
}

function axiom() {
  ./axiomcli $@ -sessionKey "$PDS_KEY"
}

#effectively connect before any action
axiom_connect
