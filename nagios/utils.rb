#!/usr/bin/ruby

STATE_OK=0
STATE_WARNING=1
STATE_CRITICAL=2
STATE_UNKNOWN=3
STATE_DEPENDENT=4

def debug(msg="")
  begin
    puts msg if DEBUG
  rescue
    #in case DEBUG is not defined
  end
end
