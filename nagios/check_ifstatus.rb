#!/usr/bin/ruby

# McData fiber switches plugin for Nagios
# Author: Jean-Baptiste BARTH <jeanbaptiste.barth@gmail.com>

# snmpwalk -c public -v 2c switch_san_a .1.3.6.1.4.1.289.2.1.1.2.3.1.1.2
# 	SNMPv2-SMI::enterprises.289.2.1.1.2.3.1.1.2.1 = INTEGER: 2
# 	SNMPv2-SMI::enterprises.289.2.1.1.2.3.1.1.2.2 = INTEGER: 2
# ...
# => 2 = OK, 6 = down, 13 = info not available
#
#my $snmpIfAdminStatus = '.1.3.6.1.2.1.2.2.1.7';
#my $snmpIfDescr = '.1.3.6.1.2.1.2.2.1.2';
#my $snmpIfOperStatus = '.1.3.6.1.2.1.2.2.1.8';
#my $snmpIfName = '.1.3.6.1.2.1.31.1.1.1.1';
#my $snmpIfAlias = '.1.3.6.1.2.1.31.1.1.1.18';
#my $snmpLocIfDescr = '.1.3.6.1.4.1.9.2.2.1.1.28';
#my $snmpIfType = '.1.3.6.1.2.1.2.2.1.3

PROGNAME=File.basename($0)
PROGPATH=File.dirname($0)
DEBUG=ENV["DEBUG"] || false

#oid taken from the equivalent perl script
oids = {
  "admin_status" => ".1.3.6.1.2.1.2.2.1.7",
  "descr" => ".1.3.6.1.2.1.2.2.1.2",
  "oper_status" => ".1.3.6.1.2.1.2.2.1.8",
  "name" => ".1.3.6.1.2.1.31.1.1.1.1",
  "type" => ".1.3.6.1.2.1.2.2.1.3",
  "in_octets" => ".1.3.6.1.2.1.2.2.1.10",
  "out_octets" => ".1.3.6.1.2.1.2.2.1.16"
}

#loading useful variables/methods
load File.join(File.dirname($0),'utils.rb')
require 'yaml'

#some useful methods for this script
def print_usage
  puts "USAGE: #{PROGNAME} <ip|host> [snmp_community] [ports_number_to_exclude]"
  puts "\tExample: #{PROGNAME} 192.168.0.50 public 15,16,17"
end

#displays interfaces, +descr if third argument=true
def dispif(interfaces,keys,descr=false)
  indexes = keys.map{|k| interfaces[k][:index]}.sort
  if descr
    indexes.map! do |i|
      k = getif(interfaces,i)
      descr = interfaces[k][:descr]
      ("#{i}" != "#{descr}" ? "#{i}" : "#{i}(#{interfaces[k][:descr]})")
    end
  end
  indexes.join(",")
end

#get interface by corrected index
def getif(interfaces,index)
  interfaces.keys.detect{|d| interfaces[d][:index] == index}
end

#checking bad number of arguments
if ARGV.length == 0
  print_usage
  exit 2
end

#parsing arguments
host = ARGV.shift
community = ARGV.shift || "public"
exclusions = (ARGV.shift || "").split(",")

#first we list interfaces and generate a sane range of numbers
#(some of our nortel switches number their interfaces from 128 to 150... very easy to use for exceptions :-)
interfaces={}
IO.popen("snmpwalk -v 2c -c #{community} #{host} .1.3.6.1.2.1.2.2.1.1").readlines.each do |line|
  i=line.chomp.split.last.to_i
  interfaces[i] = {:real_index=>i}
end
debug "interfaces (not sanitized): #{interfaces.keys.sort.join(",")}"

#snmp values
oids.each do |key,oid|
  #debug "running snmpwalk #{key} (#{oid})"
  IO.popen("snmpwalk -v 2c -c #{community} #{host} #{oid}").readlines.each do |line|
    #debug "  line: #{line}"
    interface = line.split.first.split(".").last.to_i
    unless interfaces[interface].nil?
      interfaces[interface][key.to_sym] = (line.match(/:\s*$/) ? "" : line.split(/:\s*/).last.chomp)
    end
  end
end

#sanitization
#delete virtual/internal/fictive interfaces
interfaces.delete_if{|k,v| v[:type] && !v[:type].match(/eth/i)}
#if min=128, 128 => 1 ; so translation value is 128 - 1
#NB: it's ok even if min=0 : then translation is -1, so min value is translated to 0-(-1)=+1
if interfaces.empty?
  puts "No ethernet interface !"
  exit STATE_UNKNOWN
end
translation=interfaces.keys.min - 1
interfaces.merge(interfaces) do |key,value|
  value[:index] = value[:real_index] - translation
  value
end
debug "interfaces (sanitized): #{interfaces.values.map{|v|v[:index]}.sort.join(",")}"
debug "translation : #{translation}"
#debug "Interfaces : #{interfaces.inspect}"

#output processing
not_ignored = interfaces.keys.select{|i| !exclusions.include?(interfaces[i][:index].to_s)}
debug "Not ignored : #{dispif(interfaces,not_ignored)}"
#AdminStatus is the DESIRED state
#OperStatus is the EFFECTIVE/ACTUAL state
if_down = not_ignored.select{|i| interfaces[i][:oper_status].match(/down/) }
debug "Interfaces DOWN : #{dispif(interfaces,if_down)}"
if_ok = not_ignored.select{|i| interfaces[i][:oper_status].match(/up/) }
debug "Interfaces UP : #{dispif(interfaces,if_ok)}"
if_unknown = not_ignored - if_ok - if_down
debug "Interfaces UNKNOWN : #{dispif(interfaces,if_unknown)}"
if_ok_not_normal = (interfaces.keys - not_ignored).select{|i| interfaces[i][:oper_status].match(/up/)}
debug "Interfaces IGNORED : #{dispif(interfaces,(interfaces.keys - not_ignored))}"
debug "Interfaces UP but IGNORED : #{dispif(interfaces,if_ok_not_normal)}"

#perfdatas
tmpfile = "/tmp/ifstatus_eth_#{host}"
perfdatas = {}
if File.exists?(tmpfile)
  previous = YAML.load_file(tmpfile)
  time_delta = Time.now - File.stat(tmpfile).mtime  #in seconds
  interfaces.each do |k,v|
    if previous.has_key?(k)
      perfdatas[k] = {}
      if previous[k].has_key?(:in_octets)
        delta = interfaces[k][:in_octets].to_i - previous[k][:in_octets].to_i
        delta = 0 if delta <= 0
        bandwith = (delta / time_delta / 1024).round #=> kilobytes !
        #debug "  perfdata: #{k},in : #{bandwith}"
        perfdatas[k][:in] = bandwith
      end
      if previous[k].has_key?(:out_octets)
        delta = interfaces[k][:out_octets].to_i - previous[k][:out_octets].to_i
        delta = 0 if delta <= 0
        bandwith = (delta / time_delta / 1024).round #=> kilobytes !
        #debug "  perfdata: #{k},out : #{bandwith}"
        perfdatas[k][:out] = bandwith
      end
    end
  end
end
#save interfaces
File.open(tmpfile, 'w') do |f|
  YAML.dump(interfaces, f)
end

#script results
puts "Link DOWN on interfaces : #{dispif(interfaces,if_down,true)}" unless if_down.empty?
puts "Link UP on IGNORED interfaces : #{dispif(interfaces,if_ok_not_normal,true)}
=> CHANGE THE SERVICE CONFIG ! Maybe unignore #{dispif(interfaces,if_ok_not_normal)} ?" unless if_ok_not_normal.empty?
puts "State UNKNOWN : #{dispif(interfaces,if_unknown,true)}" unless if_unknown.empty?
puts "Link UP on interfaces : #{dispif(interfaces,if_ok)}" unless if_ok.empty?
puts "Ignored: "+exclusions.join(",") unless exclusions.empty?
#perfdatas
unless perfdatas.empty?
  perf = "| "
  perfdatas.keys.sort.each do |k|
    v = perfdatas[k]
    name = (interfaces[k][:descr].match(/\w/) && "#{interfaces[k][:descr]}" != "#{k}" ? interfaces[k][:descr] : "interface_#{k}")
    perf << "in_#{name}=#{v[:in]}KB;;;0; " if v.has_key?(:in)
    perf << "out_#{name}=#{v[:out]}KB;;;0; " if v.has_key?(:out)
  end
  puts perf
end

#exit status
if !if_down.empty? || !if_ok_not_normal.empty?
  exit STATE_CRITICAL
elsif !if_unknown.empty?
  exit STATE_UNKNOWN
else
  exit STATE_OK
end
