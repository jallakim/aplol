#!/usr/bin/perl
use warnings;
use strict;
use Net::OpenSSH;
use Net::Telnet::Cisco;
use Net::Ping::External qw(ping);
use Fcntl qw(:flock);

# Reloads offline APs on ISR800 routers

# Load aplol
my $aplol_dir;
BEGIN {
	use FindBin;
	$aplol_dir = "$FindBin::Bin"; # Assume working-folder is the path where this script resides
}
use lib $aplol_dir;
use aplol;
my $aplol = aplol->new();
my %config = $aplol->get_config();

# Log
sub log_it{
	$aplol->log_it("isr800-reload", "@_");
}

# Logs debug-stuff if debug has been turned on
sub debug_log{
	$aplol->debug_log("isr800-reload", "@_");
}

# Logs error-stuff
sub error_log{
	$aplol->error_log("isr800-reload", "@_");
}

# We only want 1 instance of this script running
# Check if already running -- if so, abort.
unless (flock(DATA, LOCK_EX|LOCK_NB)) {
        die("$0 is already running. Exiting.");
}

$aplol->connect();
my $aps = $aplol->get_active_aps();

# iterate through all APs
foreach my $ap_id (sort keys %$aps){
	next if($aps->{$ap_id}{associated}); # skip online APs
	next unless($aps->{$ap_id}{model} =~ m/AP80(1|2)/i ); # skip unless ISR800 AP
		
	if($aps->{$ap_id}{neighbor_addr} =~ m/^0\.0\.0\.0$/){
		# We're missing CDP-neighbor information
		error_log("Missing CDP-information for AP '$aps->{$ap_id}{name}'. Skipping.");
		next;
	}
	
	log_it("Checking AP '$aps->{$ap_id}{name}' on switch '$aps->{$ap_id}{neighbor_name}'.");

	my $ip = $aps->{$ap_id}{neighbor_addr};
	
	if($aplol->pong($ip, 1)){
		# switch is available, log in and print output
		my $ssh = Net::OpenSSH->new(	host => $ip,
						user => $config{ssh}->{username},
						password => $config{ssh}->{password},
						timeout => 5,
						master_opts => [
							-o => "StrictHostKeyChecking=no",
							-o => "UserKnownHostsFile=/dev/null",
							-o => "LogLevel=quiet",
						]
					);
		
		unless(defined($ssh)){
			error_log("Error connecting to $ip.");
			next;
		}

		if($ssh->error){
			error_log("Error connecting to $ip: " . $ssh->error);
			next;
		}
		
		# stderr-to-stdout is needed for waitfor() in Net::Telnet::Cisco to work
		my ($pty, $err, $pid) = $ssh->open2pty({stderr_to_stdout => 1});
		
		unless(defined($pty)){
			error_log("Error connecting to $ip: $ssh->error");
		        next;
		}
		
		my $cisco = Net::Telnet::Cisco->new(
			fhopen => $pty,
			telnetmode => 0,                        # needed when using Net::OpenSSH
			cmd_remove_mode => 1,                   # needed when using Net::OpenSSH
			output_record_separator => "\r",        # needed when using Net::OpenSSH
			errmode => 'return',
			output_log => $config{path}->{ssh_log_folder} . "/cisco-output_$ip.txt",
			input_log => $config{path}->{ssh_log_folder} . "/cisco-input_$ip.txt",
			prompt => '/[#>]$/',
		);

		unless (defined($cisco)){
			error_log("Error connecting to $ip.");
			next;
		}
		
		log_it("Reloading AP '$aps->{$ap_id}{name}'");
		
		# reload the AP-module
		$cisco->print("service-module wlan-ap 0 reload");
		$cisco->print("\n");
		sleep 1;
		$cisco->print("\n");
		
		log_it("Reloaded AP '$aps->{$ap_id}{name}'");
	} else {
		# switch not available
		error_log("Switch '$aps->{$ap_id}{neighbor_name}' not reachable.");
		next;
	}
}

$aplol->disconnect();


__DATA__
Do not remove. Makes sure flock() code above works as it should.
