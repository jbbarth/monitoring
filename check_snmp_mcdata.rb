#!/usr/bin/ruby

# McData fiber switches plugin for Nagios
# Author: Jean-Baptiste BARTH <jeanbaptiste.barth@gmail.com>

# snmpwalk -c public -v 2c switch_san_a .1.3.6.1.4.1.289.2.1.1.2.3.1.1.2
# 	SNMPv2-SMI::enterprises.289.2.1.1.2.3.1.1.2.1 = INTEGER: 2
# 	SNMPv2-SMI::enterprises.289.2.1.1.2.3.1.1.2.2 = INTEGER: 2
# ...
# => 2 = OK, 6 = down, 13 = info not available

PROGNAME=File.basename($0)
PROGPATH=File.dirname($0)
DEBUG=false

#loading useful variables/methods
load File.join(File.dirname($0),'utils.rb')

#some useful methods for this script
def print_usage
  puts "USAGE: #{PROGNAME} <ip|host> <snmp_community> [ports_number_to_exclude]"
  puts "\tExample: #{PROGNAME} 192.168.0.50 public 15,16,17"
end

#checking bad number of arguments
unless (2..3).include?(ARGV.length)
  print_usage
  exit 2
end

#parsing arguments
host = ARGV.shift
community = ARGV.shift
exclusions = (ARGV.shift || "").split(",")

#retrieving snmp informations
command="snmpwalk -c #{community} -v 2c #{host} .1.3.6.1.4.1.289.2.1.1.2.3.1.1.2"
debug "command: #{command}"
result = []
IO.popen(command).readlines.each do |line|
  debug "snmpwalk result: #{line}"
  matches = line.match /\.(\d+) = INTEGER: (\d+)/
  result.push [matches[1], matches[2]]
end

#output processing
not_ignored = result.select{|x| !exclusions.include? x[0]}
interfaces_down = not_ignored.select{|v| v[1] == "6"}.map{|x| x[0]}
interfaces_ok = not_ignored.select{|v| v[1] == "2"}.map{|x| x[0]}
interfaces_unknown = not_ignored.map{|x| x[0]} - interfaces_ok - interfaces_down
interfaces_ok_not_normal = (result - not_ignored).select{|v| v[1] == "2"}.map{|x| x[0]}

#script results
puts "Link DOWN on interfaces : "+interfaces_down.join(",") unless interfaces_down.empty?
puts "Link UP on IGNORED interfaces : "+interfaces_ok_not_normal.join(",")+"\n=> CHANGE THE SERVICE CONFIG !" unless interfaces_ok_not_normal.empty?
puts "State UNKNOWN : "+interfaces_unknown.join(",") unless interfaces_unknown.empty?
puts "Link UP on interfaces : "+interfaces_ok.join(",") unless interfaces_ok.empty?
puts "Ignored: "+exclusions.join(",") unless exclusions.empty?

#exit status
if !interfaces_down.empty? || !interfaces_ok_not_normal.empty?
  exit STATE_CRITICAL
elsif !interfaces_unknown.empty?
  exit STATE_UNKNOWN
else
  exit STATE_OK
end
