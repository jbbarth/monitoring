#!/usr/bin/ruby

STATE_OK=0
STATE_WARNING=1
STATE_CRITICAL=2
STATE_UNKNOWN=3
STATE_DEPENDENT=4

def debug(msg="")
  puts msg if DEBUG
end
