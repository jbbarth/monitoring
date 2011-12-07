#!/usr/bin/ruby

PROGNAME=File.basename($0)
PROGPATH=File.dirname($0)
DEBUG=false

#loading useful variables/methods
load File.join(File.dirname($0),'utils.rb')

#help
def print_usage
  puts "USAGE: #{PROGNAME} <ip|host:port> [community-string] [warning-cpu,critical-cpu] [warning-heap,critical-heap] [warning-threads,critical-threads]"
  puts "  Default values:"
  puts "    community: public"
  puts "    cpu    : 1,25,50  : monitor_cpu = yes (0 for no), warning limit = 25%, critical limit = 50%"
  puts "    heap   : 1,80,90  : monitor_heap(memory) = yes (0 for no), warning limit = 80%, critical limit = 90%"
  puts "    threads: 1,75,100 : monitor_threads = yes (0 for no), warning limit = 75%, critical limit = 100%"
end

#checking bad number of arguments
if ARGV.length == 0
  print_usage
  exit STATE_CRITICAL
end

host,port=ARGV.shift.split(":")
community=ARGV.shift || "public"
cpu=(ARGV.shift || "1,25,50").split(",")
heap=(ARGV.shift || "1,80,90").split(",")
threads=(ARGV.shift || "1,75,100").split(",")
debug "params: cpu: #{cpu.join(",")} / heap: #{heap.join(",")} / threads: #{threads.join(",")}"

#return values
output=[]
perfdata=[]
retval=[]

#cpu check
if cpu.shift == "1"
  command = "#{PROGPATH}/check_jvm_cpu.rb #{host}:#{port} #{cpu.shift},#{cpu.shift} #{community}"
  debug "command: #{command}"
  IO.popen(command) do |f|
    result = f.read.chomp.split("|")
    output << result.shift
    perfdata << result.shift
    debug "output  : #{output.inspect}"
    debug "perfdata: #{perfdata.inspect}"
  end
  retval << $?.exitstatus
end

#heap check
if heap.shift == "1"
  command = "#{PROGPATH}/check_jvm_memory.sh #{host}:#{port} #{community} #{heap.shift},#{heap.shift}"
  debug "command: #{command}"
  IO.popen(command) do |f|
    result = f.read.chomp.split("|")
    output << result.shift
    perfdata << result.shift
    debug "output  : #{output.inspect}"
    debug "perfdata: #{perfdata.inspect}"
  end
  retval << $?.exitstatus
end

#threads check
if threads.shift == "1"
  command = "#{PROGPATH}/check_jvm_threads.sh #{host}:#{port} #{community} #{threads.shift},#{threads.shift}"
  debug "command: #{command}"
  IO.popen(command) do |f|
    result = f.read.chomp.split("|")
    output << result.shift
    perfdata << result.shift
    debug "output  : #{output.inspect}"
    debug "perfdata: #{perfdata.inspect}"
  end
  retval << $?.exitstatus
end

#sanitize output and perfdata
output = output.compact.map{|x| x.chomp.strip}
perfdata = perfdata.compact.map{|x| x.chomp.strip}

#output
perfdata=(perfdata.empty? ? "" : "| #{perfdata.join(" ")}")
puts "#{output.join(" / ")} #{perfdata}"
exit (retval.empty? ? STATE_UNKNOWN : retval.max)
