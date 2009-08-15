#!/usr/bin/ruby

# Plugin to check CPU usage for Nagios
#
# This plugin checks the value of ssCpuRaw* counters :
# - if there's a file named "/tmp/cpu_avg_<machine>", make a difference and output the result
# - if not, exit with UNKNOWN state, and you'll have to wait for next Nagios check
# See check_cpu_load.rb for more common (but stupid imho) behaviour
#
# Author: Jean-Baptiste BARTH <jeanbaptiste.barth@gmail.com>

# snmpwalk -v 2c -c public myserver .1.3.6.1.4.1.2021.11
# 	[...]
#	UCD-SNMP-MIB::ssCpuRawUser.0 = Counter32: 1376927
#	UCD-SNMP-MIB::ssCpuRawNice.0 = Counter32: 2145
#	UCD-SNMP-MIB::ssCpuRawSystem.0 = Counter32: 950540
#	UCD-SNMP-MIB::ssCpuRawIdle.0 = Counter32: 2145508399
#	UCD-SNMP-MIB::ssCpuRawWait.0 = Counter32: 13086118
#	UCD-SNMP-MIB::ssCpuRawKernel.0 = Counter32: 911293
#	UCD-SNMP-MIB::ssCpuRawInterrupt.0 = Counter32: 5918
#	[...]

PROGNAME=File.basename($0)
PROGPATH=File.dirname($0)
DEBUG=false
LIMIT32=(2 ** 32)

#loading useful variables/methods
load File.join(File.dirname($0),'utils.rb')
require 'yaml'

#some useful methods for this script
def print_usage
  puts "USAGE: #{PROGNAME} <ip|host> [warning,critical] [snmp_community]"
  puts "  Default values: warning=80, critical=90, snmp_community=public"
end

#checking bad number of arguments
unless (1..3).include?(ARGV.length)
  print_usage
  exit 2
end

#our own substraction method
#Counter32 counters have a max limit..
def minus(a,b)
  (a < b ? LIMIT32 - a + b : a - b)
end

#parsing arguments
host = ARGV.shift
limits = (ARGV.shift || "80,90").split(",")
community = ARGV.shift || "public"
tmpfile = "/tmp/cpu_avg_#{host}"

#retrieving snmp informations
command="snmpwalk -c #{community} -v 2c #{host} .1.3.6.1.4.1.2021.11"
snmp_now = {}
IO.popen(command).readlines.grep(/ssCpuRaw/).each do |line|
  res = line.chomp.scan(/(ssCpuRaw\S*) .* (\d+$)/).flatten
  debug "snmpwalk result: #{res.join(' ')}"
  snmp_now[res.first] = res[1].to_i
end

#wether it's first call or not
if File.exists?(tmpfile)
  #calculate deltas
  delta = {}
  snmp_previous = YAML.load_file(tmpfile)
  snmp_now.each_pair do |k,v|
    delta[k] = minus(v,snmp_previous[k]) if snmp_previous.has_key?(k)
  end
  debug "delta: #{delta.to_a.inspect}"
end

#we save the new values for next time
debug "saving tmpfile to #{tmpfile}"
File.open(tmpfile, 'w') do |f|
  YAML.dump(snmp_now, f)
end

#now we can exit if there's no delta
unless delta
  puts "No previous data, waiting for next check..."
  exit STATE_UNKNOWN
end

#calculate the total number of ticks
ticks = delta.values.inject(0){|sum,n| sum + n}
debug "total ticks = #{ticks}"

#and then the percentage of ticks per category
percents = {}
delta.each_pair do |key,value|
  new_key = key.scan(/ssCpuRaw(.*)/).join
  new_new_key = new_key.gsub(/.\d+/,"")
  new_key = new_new_key unless percents[new_new_key]
  percents[new_key] = value.to_f * 100 / ticks.to_f
end
debug "percents: #{percents.to_a.inspect}"
#[["Interrupt", "0.00"], ["Wait", "0.17"], ["System", "0.00"], ["User", "0.00"], ["Nice", "0.00"], ["Kernel", "0.00"], ["SoftIRQ", "0.00"], ["Idle", "33.17"]]

#cpu percent used ?
cpu_used = 100 - percents["Idle"]

#result for main counters
percents["Other"] = percents.dup.delete_if do |k,v|
  k.match /User|System|Idle|Wait|Nice/
end.values.inject(0) do |sum,n|
  sum = sum + n
end
result = percents.delete_if do |k,v|
  !k.match /User|System|Idle|Wait|Nice|Other/
end.to_a.map do |a|
  %Q(#{a[0]}=#{"%.1f" % a[1]}%)
end.join(", ").gsub(/\.?0+%/,"%")

#output and exit state
if ticks == 0
  puts "CPU Used UNKNOWN: maybe you should slow down your checks"
  exit STATE_UNKNOWN
elsif cpu_used > limits[1].to_f
  puts "CPU Used CRITICAL: #{'%.1f' % cpu_used}% > #{limits[1]} - #{result}"
  exit STATE_CRITICAL
elsif cpu_used > limits[0].to_f
  puts "CPU Used WARNING: #{'%.1f' % cpu_used}% > #{limits[0]} - #{result}"
  exit STATE_WARNING
else
  puts "CPU Used OK: #{'%.1f' % cpu_used}% - #{result}"
  exit STATE_OK
end
