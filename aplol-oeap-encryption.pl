#!/usr/bin/perl
use warnings;
use strict;
use Net::OpenSSH;
use Net::Telnet::Cisco;
use Net::Ping::External qw(ping);
use Fcntl qw(:flock);

# Enables Data Encryption on /all/ online APs on DMZ WLCs

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
	$aplol->log_it("oeap-encryption", "@_");
}

# Logs debug-stuff if debug has been turned on
sub debug_log{
	$aplol->debug_log("oeap-encryption", "@_");
}

# Logs error-stuff
sub error_log{
	$aplol->error_log("oeap-encryption", "@_");
}

# We only want 1 instance of this script running
# Check if already running -- if so, abort.
unless (flock(DATA, LOCK_EX|LOCK_NB)) {
        die("$0 is already running. Exiting.");
}

$aplol->connect();
my $wlcs = $aplol->get_wlcs();

# iterate through all WLCs
foreach my $wlc_id (sort keys %$wlcs){
	next unless($wlcs->{$wlc_id}{active}); # skip non-active WLCs
	next unless($wlcs->{$wlc_id}{name} =~ m/dmz/i ); # skip unless DMZ
		
	# At this point we have active DMZ WLC
	# All APs should have Data Encryption enabled on these
	
	log_it("Logging in to WLC '$wlcs->{$wlc_id}{name}' to enable Data Encryption.");
	
	my $ip = $wlcs->{$wlc_id}{ipv4};
	
	if($aplol->pong($ip, 1)){
		# WLC is available, log in and print output
		my $ssh = Net::OpenSSH->new(	host => $ip,
						user => $config{wlc}->{username},
						password => $config{wlc}->{password},
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
		
		my $cisco = Net::Telnet->new(
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
		
		# Log in (due to LOL WLC)
		$cisco->waitfor('/user: $/i');
		$cisco->print($config{wlc}->{username});
		$cisco->waitfor('/password:$/i');
		$cisco->print($config{wlc}->{password});
		$cisco->waitfor('/>$/i');
		
		log_it("Activating Data Encryption on all APs (if applicable) on WLC '$wlcs->{$wlc_id}{name}'.");
		
		$cisco->print("config ap link-encryption enable all");
		$cisco->waitfor('/Are you sure ? (y/N) $/i');
		$cisco->print("y");
		$cisco->waitfor('/>$/i');
		$cisco->print("logout");
		
		log_it("Data Encryption activated on WLC '$wlcs->{$wlc_id}{name}'");

	} else {
		# switch not available
		error_log("WLC '$wlcs->{$wlc_id}{name}' not reachable.");
		next;
	}
}

$aplol->disconnect();


__DATA__
Do not remove. Makes sure flock() code above works as it should.
