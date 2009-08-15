#!/usr/bin/ruby

# Plugin to check CPU usage (all but idle) for Nagios
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
min_ticks = 2000
max_cycle = 15

#retrieving snmp informations
command="snmpwalk -c #{community} -v 2c #{host} .1.3.6.1.4.1.2021.11"
snmp = {}
ticks = 0
cycle = 0

while cycle < max_cycle && ticks < min_ticks do
  debug "running command (cycle #{cycle}): #{command}"
  sleep 1 unless cycle == 0
  IO.popen(command).readlines.grep(/ssCpuRaw/).each do |line|
    res = line.chomp.scan(/(ssCpuRaw\S*) .* (\d+$)/).flatten
    debug "snmpwalk result: #{res.join(' ')}"
    if snmp[res.first]
      snmp[res.first][:delta] = snmp[res.first][:delta] + minus(res[1].to_i,snmp[res.first][:current])
      snmp[res.first][:current] = res[1].to_i
    else
      snmp[res.first] = {:current => res[1].to_i, :delta => 0}
    end
  end
  ticks = snmp.values.inject(0){|sum,n| sum + n[:delta]} unless cycle == 0
  debug "total ticks: #{ticks}"
  cycle += 1
end

percents = {}
snmp.each_pair do |key,value|
  new_key = key.scan(/ssCpuRaw(.*)/).join
  new_new_key = new_key.gsub(/.\d+/,"")
  new_key = new_new_key unless percents[new_new_key]
  percents[new_key] = value[:delta].to_f * 100 / ticks.to_f
end
debug "percents: #{percents.to_a.inspect}"
#[["Interrupt", "0.00"], ["Wait", "0.17"], ["System", "0.00"], ["User", "0.00"], ["Nice", "0.00"], ["Kernel", "0.00"], ["SoftIRQ", "0.00"], ["Idle", "33.17"]]

#cpu percent used ?
cpu_used = 100 - percents["Idle"]

#result for main counters
result = percents.delete_if{|k,v| !k.match /User|System|Nice|Idle|Wait/ }.to_a.map{|a| %Q(#{a[0]}=#{"%.2f" % a[1]}%)}.join(", ")

#output and exit state
if ticks == 0
  puts "CPU Used UNKNOWN: maybe you should tune max_cycle and/or min_ticks settings"
  exit STATE_UNKNOWN
elsif cpu_used > limits[1].to_f
  puts "CPU Used CRITICAL: #{'%.2f' % cpu_used}% > #{limits[1]} | #{result}"
  exit STATE_CRITICAL
elsif cpu_used > limits[0].to_f
  puts "CPU Used WARNING: #{'%.2f' % cpu_used}% > #{limits[0]} | #{result}"
  exit STATE_WARNING
else
  puts "CPU Used OK: #{'%.2f' % cpu_used}% | #{result}"
  exit STATE_OK
end
