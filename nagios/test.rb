#!/usr/bin/ruby

require "snmp"
 
ip="localhost"
community = "public"
 
manager=SNMP::Manager.new(:Host => "#{ip}", :Community => "#{community}")

begin
  version = manager.get_value("osysDescr.0")
rescue ArgumentError
  version = "unknown value"
end
 
puts "version IOS pour #{ip} : #{version}"
