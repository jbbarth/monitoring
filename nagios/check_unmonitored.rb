#!/usr/bin/ruby

# Goal: This script scans a given network and searchs for machines 
# that are not monitored so you can keep your Nagios up to date.
# 
# Author: Jean-Baptiste BARTH <jeanbaptiste.barth@gmail.com>
#
# The script compares a list of subnets or ips to scan (given 
# with -s or -S option), and compares it to machines monitored 
# by parsing Nagios config file. The machine is then considered 
# as unmonitored unless IP is in exception list (given with -e 
# or -E option). WARNING: this scripts needs "fping" in order to 
# scan the network.
#
# Usage: check_unmonitored.rb [options], where options can be:
#   Nagios return options:
#     -c, --critical <N> : if number of unmonitored machines is > N, then exit with a critical status
#     -w, --warning <N> : else if number of unmonitored machines is > N, then exit with a warning status
#   Script parameters:
#     -f, --fping </alternative/path/to/fping>
#     -n, --nagiosconf </alternative/path/to/hosts.cfg>
#     -s, --subnet <subnet1,subnet2,...>
#     -S, --subnetfile <path/to/subnet.txt> (one network or ip per line, comments allowed)
#     -e, --except <ip1,ip2,...>
#     -E, --exceptfile <path/to/except.txt> (one ip per line, comments allowed)
#     --no-dns : do not perform DNS resolution
#   Other:
#     -h, --help (display this help)
#
# You have to specify at least one subnet or ip to scan with -s or -S option.
#
# Default values are :
#   -f : /usr/bin/fping
#   -n : /etc/nagios/hosts.cfg
#   -c : 10
#   -w : 0

# Common constants
PROGNAME=File.basename($0)
PROGPATH=File.dirname($0)

# Useful libs
require 'getoptlong'
require 'rdoc/usage'

# Useful variables/methods
load File.join(File.dirname($0),'utils.rb')

# Arguments parsing
opts = GetoptLong.new(
  [ '--critical', '-c', GetoptLong::REQUIRED_ARGUMENT ],
  [ '--warning', '-w', GetoptLong::REQUIRED_ARGUMENT ],
  [ '--fping', '-f', GetoptLong::REQUIRED_ARGUMENT ],
  [ '--nagiosconf', '-n', GetoptLong::REQUIRED_ARGUMENT ],
  [ '--subnet', '-s', GetoptLong::REQUIRED_ARGUMENT ],
  [ '--subnetfile', '-S', GetoptLong::REQUIRED_ARGUMENT ],
  [ '--except', '-e', GetoptLong::REQUIRED_ARGUMENT ],
  [ '--exceptfile', '-E', GetoptLong::REQUIRED_ARGUMENT ],
  [ '--no-dns', GetoptLong::NO_ARGUMENT ],
  [ '--debug', '-d', GetoptLong::NO_ARGUMENT ],
  [ '--help', '-h', GetoptLong::NO_ARGUMENT ]
)

# Default options
critical = 10
warning = 0
fping="/usr/bin/fping"
nagiosconf = "/etc/nagios/hosts.cfg"
subnets = Array.new
excepts = Array.new
resolve = true

# Function to parse config files
def readconf(file)
  begin
    File.readlines(file).map do |a|
      b = a.chomp.split.first.gsub(/#.*/,'')
      (b.match(/^\s*$/) ? nil : b)
    end.compact
  rescue
    $stderr.puts "ERROR: Unable to read #{file} : #{$!}"
    exit STATE_UNKNOWN
  end
end

# Function to get a number from command line
def getinteger(arg)
  arg.strip!
  if arg.match(/^\d+$/)
    arg.to_i
  else
    $stderr.puts "ERROR: Not a number : #{arg}"
    exit STATE_UNKNOWN
  end
end

# Effective parsing
opts.each do |opt, arg|
  case opt
    when '--help'
      RDoc::usage
    when '--critical'
      critical = getinteger(arg)
    when '--warning'
      warning = getinteger(arg)
    when '--fping'
      fping = arg
    when '--nagiosconf'
      if File.readable?(arg)
        nagiosconf = arg
      else
        $stderr.puts "ERROR: Supplied nagios config file #{arg} is not readable."
        exit STATE_UNKNOWN
      end
    when '--subnet'
      subnets << arg.split(",")
    when '--subnetfile'
      subnets << readconf(arg)
    when '--except'
      excepts << arg.explode(",")
    when '--exceptfile'
      excepts << readconf(arg)
    when '--no-dns'
      resolve = false
    when '--debug'
      DEBUG=true
  end
end
subnets.flatten!
excepts.flatten!

# In case of no subnet given
if subnets.length == 0
  $stderr.puts "ERROR: No subnet given !"
  $stderr.puts "Run #{$0} --help"
  exit STATE_UNKNOWN
end

# Check fping is installed
unless File.executable?(fping)
  $stderr.puts "ERROR: #{fping} is not here or not executable ; is it installed?"
  exit STATE_UNKNOWN
end

# Params values for debugging
debug "Subnets/IPs:: #{subnets.inspect}"
debug "Exceptions: #{excepts.inspect}"
debug "Nagios conf: #{nagiosconf}"
debug "Warning limit: #{warning}"
debug "Critical limit: #{critical}"

# Scan the network with fping
servers = Array.new
threads = Array.new
subnets.each do |subnet|
  threads << Thread.new do
    debug "  scanning #{subnet}"
    res = IO.popen("#{fping} -i 10 -r 1 -g #{subnet} 2>/dev/null | grep 'is alive'")
    res.each do |line|
      line.scan(/(\S+)\s+is alive/) do |m|
        debug "  detected #{m.first}"
        servers << m.first
      end
    end unless res.nil?
  end
end
threads.map{ |x| x.join }
debug "Detected on the network: #{servers.join("\n")}"

# Get hosts in Nagios conf
monitored = Array.new
f = File.read(nagiosconf)
f.scan(/define\s+host\s+\{[^}]+\}\s*/m) do |section|
  debug "Section:\n#{section}"
  a = section.split(/\n+/).select{|x| x.match(/host_name|address/)}
  a.map!{|x| x.strip}
  monitored << a.grep(/address/).first.split(/\s+/)[1]
end
debug "Detected monitored: #{monitored.join("\n")}"

# Compare results
missing = Array.new
servers.each do |s|
  unless monitored.include?(s) || excepts.include?(s)
    debug "  unmonitored: #{s}"
    if resolve
      debug "  dns resolution: #{s}"
      host = `getent hosts #{s}`
      missing << s+("#{host}" == "" ? " (*unknown*)" : " (#{host.chomp.split.last})")
    else
      missing << s
    end
  end
end

# Output & return value
if missing.length == 0
  puts "OK: all machines monitored"
  exit STATE_OK
elsif missing.length <= warning
  puts "OK, but #{missing.length} unmonitored machine(s)\n#{missing.join("\n")}"
  exit STATE_OK
elsif missing.length <= critical
  puts "WARNING: #{missing.length} unmonitored machine(s)\n#{missing.join("\n")}"
  exit STATE_WARNING
else
  puts "CRITICAL: #{missing.length} unmonitored machine(s)\n#{missing.join("\n")}"
  exit STATE_CRITICAL
end
