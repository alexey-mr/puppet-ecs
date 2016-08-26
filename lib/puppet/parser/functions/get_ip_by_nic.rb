require 'facter'

module Puppet::Parser::Functions
  newfunction(:get_ip_by_nic, :type => :rvalue) do |args|
    nic = args[0]
    return Facter.value('ipaddress_%s' % nic)
  end
end
