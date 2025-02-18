############################################################
# This section verifies start, stop, and restart after
# installation within a new EC2 instance spun up by Kitchen.
#
# - stop mongod so that we begin testing from a stopped state
# - verify start, stop, and restart
############################################################

# service is not in path for commands with sudo on suse
service = os[:name] == 'suse' ? '/sbin/service' : 'service'

describe command("#{service} mongod stop") do
  its('exit_status') { should eq 0 }
end

describe command("#{service} mongod start") do
  its('exit_status') { should eq 0 }
end

# Inspec treats all amazon linux as upstart, we explicitly make it use
# systemd_service https://github.com/chef/inspec/issues/2639
if (os[:name] == 'amazon' and os[:release] == '2.0')
  describe systemd_service('mongod') do
    it { should be_running }
  end
else
  describe service('mongod') do
    it { should be_running }
  end
end

describe command("#{service} mongod stop") do
  its('exit_status') { should eq 0 }
end

describe command("#{service} mongod restart") do
  its('exit_status') { should eq 0 }
end

if (os[:name] == 'amazon' and os[:release] == '2.0')
  describe systemd_service('mongod') do
    it { should be_running }
  end
else
  describe service('mongod') do
    it { should be_running }
  end
end

if os[:arch] == 'x86_64'
  # install_compass does not run Amazon Linux but *does* run on Amazon Linux 2,
  # but the 'redhat' family includes both, apparently. We need to specifically
  # exclude Amazon Linux from the set of allowed distributions here because the
  # version strings would otherwise pass it.
  if ((os[:family] == 'redhat' and os[:name] != "amazon" and os[:release].split('.')[0].to_i >= 7) or
      (os[:name] == 'ubuntu' and os[:release].split('.')[0].to_i >= 16) or
      (os[:name] == 'debian' and os[:release].split('.')[0].to_i >= 9) or
      (os[:name] == 'amazon' and os[:release].split('.')[0].to_i == 2))
    describe command("install_compass") do
      its('exit_status') { should eq 0 }
      its('stderr') { should eq '' }
    end
  elsif os[:name] == 'suse'
    describe command("install_compass") do
      its('exit_status') { should eq 1 }
      its('stderr') { should match /You are using an unsupported platform/ }
    end
  else
    describe command("install_compass") do
      its('exit_status') { should eq 1 }
      its('stderr') { should match /You are using an unsupported Linux distribution/ }
    end
  end
else
  describe command("install_compass") do
    its('exit_status') { should eq 1 }
    its('stderr') { should match /Sorry, MongoDB Compass is only supported on 64-bit Intel platforms/ }
  end
end

############################################################
# This section verifies files, directories, and users
# - files and directories exist and have correct attributes
# - mongod user exists and has correct attributes
############################################################

# convenience variables for init system and package type
upstart = (os[:name] == 'ubuntu' && os[:release][0..1] == '14') ||
          (os[:name] == 'amazon')
sysvinit = if (os[:name] == 'debian' && os[:release][0] == '7') ||
              (os[:name] == 'redhat' && os[:release][0] == '6') ||
              (os[:name] == 'suse' && os[:release][0..1] == '11') ||
              (os[:name] == 'ubuntu' && os[:release][0..1] == '12')
             true
           else
             false
           end
systemd = !(upstart || sysvinit)
rpm = if os[:name] == 'amazon' || os[:name] == 'redhat' || os[:name] == 'suse'
        true
      else
        false
      end
deb = !rpm

# these files should exist on all systems
%w(
  /etc/mongod.conf
  /usr/bin/mongod
  /var/log/mongodb/mongod.log
).each do |filename|
  describe file(filename) do
    it { should be_file }
  end
end

if sysvinit
  describe file('/etc/init.d/mongod') do
    it { should be_file }
    it { should be_executable }
  end
end

if systemd
  unit_file_prefix = ''
  if os[:name] == 'suse'
    # Putting systemd unit files in /usr, which may be a separate partition
    # and therefore not available during isolated startups, is bad practice.
    # But it's what SUSE has chosen to do, so we have to deal with it.
    unit_file_prefix = '/usr'
  end
  describe file("#{unit_file_prefix}/lib/systemd/system/mongod.service") do
    it { should be_file }
  end
end

if rpm
  %w(
    /var/lib/mongo
    /var/run/mongodb
  ).each do |filename|
    describe file(filename) do
      it { should be_directory }
    end
  end

  describe user('mongod') do
    it { should exist }
    its('groups') { should include 'mongod' }
    its('home') { should eq '/var/lib/mongo' }
    its('shell') { should eq '/bin/false' }
  end
end

if deb
  describe file('/var/lib/mongodb') do
    it { should be_directory }
  end

  describe user('mongodb') do
    it { should exist }
    its('groups') { should include 'mongodb' }
    # All versions of Debian 10 will use /usr/sbin/nologin for service
    # account shells
    its('shell') {
      if ((os[:name] == 'debian' and os[:release].split('.')[0] >= '10') or
          (os[:name] == 'ubuntu' and os[:release] == '18.04') or
          (os[:name] == 'ubuntu' and os[:release] == '20.04') or
          (os[:name] == 'ubuntu' and os[:release] == '22.04')
          )
        should eq '/usr/sbin/nologin'
      else
        should eq '/bin/false'
      end
    }
  end
end

############################################################
# This section verifies ulimits.
############################################################

ulimits = {
  'Max file size'     => 'unlimited',
  'Max cpu time'      => 'unlimited',
  'Max address space' => 'unlimited',
  'Max open files'    => '64000',
  'Max resident set'  => 'unlimited',
  'Max processes'     => '64000'
}
ulimits_cmd = 'cat /proc/$(pgrep mongod)/limits'

ulimits.each do |limit, value|
  describe command("#{ulimits_cmd} | grep \"#{limit}\"") do
    its('stdout') { should match(/#{limit}\s+#{value}/) }
  end
end

############################################################
# This section verifies uninstall.
############################################################

if rpm
  describe command('rpm -e $(rpm -qa | grep "mongodb.*server" | awk \'{print $1}\')') do
    its('exit_status') { should eq 0 }
  end
elsif deb
  describe command('dpkg -r $(dpkg -l | grep "mongodb.*server" | awk \'{print $2}\')') do
    its('exit_status') { should eq 0 }
  end
end

# make sure we cleaned up
%w(
  /lib/systemd/system/mongod.service
  /usr/bin/mongod
).each do |filename|
  describe file(filename) do
    it { should_not exist }
  end
end
