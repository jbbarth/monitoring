#!/usr/bin/ruby

# Plugin to check Java instance CPU usage for Nagios
#
# This plugin checks the value of *CpuTimeNs* counters :
# - if there's a file named "/tmp/acai_cpu_avg_<instance>", make a difference and output the result
# - if not, exit with UNKNOWN state, and you'll have to wait for next Nagios check
#
# Author: Jean-Baptiste BARTH <jeanbaptiste.barth@gmail.com>
#
# FIRST SOLUTION (not used):
#
# snmpwalk -v2c -c public acaiprod2:10093 .1.3.6.1.4.1.42.2.145.3.163.1.1.3.10.1.8
#  JVM-MANAGEMENT-MIB::jvmThreadInstCpuTimeNs.'........' = Counter64: 5150000000 nanoseconds
#  JVM-MANAGEMENT-MIB::jvmThreadInstCpuTimeNs.'........' = Counter64: 140000000 nanoseconds
#  JVM-MANAGEMENT-MIB::jvmThreadInstCpuTimeNs.'........' = Counter64: 410000000 nanoseconds
#  JVM-MANAGEMENT-MIB::jvmThreadInstCpuTimeNs.'........' = Counter64: 0 nanoseconds
#  JVM-MANAGEMENT-MIB::jvmThreadInstCpuTimeNs.'........' = Counter64: 560000000 nanoseconds
#  JVM-MANAGEMENT-MIB::jvmThreadInstCpuTimeNs.'........' = Counter64: 0 nanoseconds
#  JVM-MANAGEMENT-MIB::jvmThreadInstCpuTimeNs.'........' = Counter64: 0 nanoseconds
#  JVM-MANAGEMENT-MIB::jvmThreadInstCpuTimeNs.'........' = Counter64: 0 nanoseconds
#  JVM-MANAGEMENT-MIB::jvmThreadInstCpuTimeNs.'........' = Counter64: 0 nanoseconds
# snmpwalk -v2c -c public acaiprod2:10093 .1.3.6.1.4.1.42.2.145.3.163.1.1.3.10.1.8 | cut -d" " -f 4 | ruby -ne 'puts readlines.inject(0){|sum,i|sum+i.to_i/1000000}'
# => number of milliseconds of cpu used for this jvm instance
#
# SECOND SOLUTION (used in this script):
# 1) get the pid via :
#  snmpwalk -v2c -c public acaiprod2:10093 .1.3.6.1.4.1.42 |grep -i 24631
#      => JVM-MANAGEMENT-MIB::jvmRTName.0 = STRING: 24631@acaiprod2.setra.fr
#      => pid is 24631
# 2) get the cpu used by this pid :
#   snmpwalk -c public -v 2c acaiprod2 1.3.6.1.2.1.25.5.1.1.1.24631
#      => HOST-RESOURCES-MIB::hrSWRunPerfCPU.24631 = INTEGER: 22352
#      => 22352 centiseconds
# 3) make the difference between two values (large amount of time between the 
#    two measures if we want to be a minimum precise) ; values are stored in
#    /tmp/jvm_cpu_<hostaddress>:<jvmsnmpport>_<pid>


PROGNAME=File.basename($0)
PROGPATH=File.dirname($0)
DEBUG=false
LIMIT64=(2 ** 64) #because we have a "Counter64"

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
#Counter64 counters have a max limit..
def minus(a,b)
  (a < b ? LIMIT64 - a + b : a - b)
end

#parsing arguments
host, port = ARGV.shift.split(":")
limits = (ARGV.shift || "80,90").split(",")
community = ARGV.shift || "public"

#retrieve port
#.1.3.6.1.4.1.42.2.145.3.163.1.1.4.1.0 = JVM-MANAGEMENT-MIB::jvmRTName.0
#see: snmptranslate -On JVM-MANAGEMENT-MIB::jvmRTName.0
pid = IO.popen("snmpwalk -c #{community} -v 2c #{host}:#{port} .1.3.6.1.4.1.42.2.145.3.163.1.1.4.1.0").read
#=> "JVM-MANAGEMENT-MIB::jvmRTName.0 = STRING: 24631@acaiprod2.setra.fr\n"
pid = pid.scan(/(\d+)@/).to_s
#=> "24631"
debug "pid: #{pid}"
if pid.empty?
  $stderr.puts "CPU(UNKNOWN): no snmp response from #{host}:#{port}"
  exit STATE_UNKNOWN
end

#retrieve cpu counter for this pid
counter = IO.popen("snmpwalk -c #{community} -v 2c #{host} .1.3.6.1.2.1.25.5.1.1.1.#{pid}").read
#=> HOST-RESOURCES-MIB::hrSWRunPerfCPU.24631 = INTEGER: 30717
counter = counter.split.last
#=> 30717
debug "counter (0.01s): #{counter}"
counter = "#{counter.to_i * 10}"
debug "counter (ms): #{counter}"
if counter.empty?
  $stderr.puts "CPU(UNKNOWN): no snmp response from #{host}"
  exit STATE_UNKNOWN
end

tmpfile = "/tmp/acai_cpu_#{host}:#{port}_#{pid}"
#wether it's first call or not
if File.exists?(tmpfile)
  #dont consider if we get a too old file (not modified since 30 mins = 1800s = 1800000ms)...
  time_delta = (Time.now - File.stat(tmpfile).mtime) * 1000
  debug "time_delta(ms): #{time_delta}"
  if time_delta < 1800000
    #calculate delta
    counter_previous = File.read(tmpfile).chomp
    delta = minus(counter.to_i,counter_previous.to_i)
    debug "delta(ms): #{delta.inspect}"
  end
end

#we save the new values for next time
debug "saving counter to tmpfile #{tmpfile}"
File.open(tmpfile, 'w') do |f|
  f.puts counter
end

#now we can exit if there's no delta
unless delta
  puts "CPU(UNKNOWN): No previous data, waiting for next check..."
  exit STATE_UNKNOWN
end

#percentage of cpu usage
percentage = delta / time_delta * 100
debug "percentage: #{percentage}"

#output and exit state
if time_delta <= 5000
  puts "CPU(UNKNOWN): maybe you should slow down your checks ? (time difference <5s)"
  exit STATE_UNKNOWN
elsif percentage > limits[1].to_f
  puts "CPU(CRITICAL): #{'%.1f' % percentage}% > #{limits[1]}"
  exit STATE_CRITICAL
elsif percentage > limits[0].to_f
  puts "CPU(WARNING): #{'%.1f' % percentage}% > #{limits[0]}"
  exit STATE_WARNING
else
  puts "CPU(OK): #{'%.1f' % percentage}%"
  exit STATE_OK
end
