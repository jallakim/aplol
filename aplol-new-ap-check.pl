#!/usr/bin/perl
use warnings;
use strict;
use Getopt::Long;
use Text::CSV;
use File::BOM qw( :all );
use Net::OpenSSH;
use Net::Telnet::Cisco;
use Net::Ping::External qw(ping);
use Fcntl qw(:flock);
use Term::ANSIColor;

# Takes a list of APs, and checks wether or not they are online
# If they are not online, it checks a list of switches for MAC/CDP neighbor information
# Useful when you want to do a quick overview of new installs

# Expects a list of switches/routers to check as STDIN
# Also needs a CSV-file containing the APs, given by the "--ap" argument.
#   rs edg-hds-h | perl $thisfile --ap $ap_csv

# --sep/--separator can be used to override default separator (comma)

# Example;
#   rs edg-hds-h | grep -E "(rs[0-9]-Lo1900|sw[0-9]-Vl1900)" | perl aplol-new-ap-check.pl --ap /home/user/file.csv --sep ';'

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
	$aplol->log_it("new-ap-check", "@_");
}

# Logs debug-stuff if debug has been turned on
sub debug_log{
	$aplol->debug_log("new-ap-check", "@_");
}

# Logs error-stuff
sub error_log{
	$aplol->error_log("new-ap-check", "@_");
}

# Ping stuff
sub pong{
        my ($ip, $timeout) = @_;
        my $pong = 0;
        my $tries = 0;
        
        while(($pong == 0) && ($tries < $timeout)){
                if(ping(host => $ip, count => 1, timeout => 1)){
                        $pong = 1;
                }
                
                $tries++;
        }
        return $pong;   
}

# We only want 1 instance of this script running
# Check if already running -- if so, abort.
unless (flock(DATA, LOCK_EX|LOCK_NB)) {
        die("$0 is already running. Exiting.");
}

# Get options
my ($ap_csv, $csv_sep);
if (@ARGV > 0) {
	GetOptions(
		'ap=s'			=> \$ap_csv,
		'sep|separator=s'	=> \$csv_sep,
	)
}

# Check if required parameters is set
unless($ap_csv){
	die(error_log("Required parameters not set. Exiting."));
}

$aplol->connect();
my $pi_aps = $aplol->get_active_aps();
my %sw_aps;

# Gather info from all switches/routers
while (my $switch = <STDIN>) {
	chomp($switch);
	next unless ($switch =~ m/^(.+?)\s\((.+?)\)\s(.+)$/);
	my ($hostname, $ip, $model) = ($1, $2, $3);

	if(pong($ip, 1)){
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
			log_it("Error connecting to $ip.");
			next;
		}

		if($ssh->error){
			log_it("Error connecting to $ip: " . $ssh->error);
			next;
		}
		
		# stderr-to-stdout is needed for waitfor() in Net::Telnet::Cisco to work
		my ($pty, $err, $pid) = $ssh->open2pty({stderr_to_stdout => 1});
		
		unless(defined($pty)){
			log_it("Error connecting to $ip: $ssh->error");
		        next;
		}
		
		my $cisco = Net::Telnet::Cisco->new(
			fhopen => $pty,
			telnetmode => 0,                        # needed when using Net::OpenSSH
			cmd_remove_mode => 1,                   # needed when using Net::OpenSSH
			output_record_separator => "\r",        # needed when using Net::OpenSSH
			errmode => 'return',
			output_log => "$config{path}->{ssh_log_folder}/cisco-output_$ip.txt",
			input_log => "$config{path}->{ssh_log_folder}/cisco-input_$ip.txt",
			prompt => '/[#>]$/',
		);

		unless (defined($cisco)){
			log_it("Error connecting to $ip.");
			next;
		}
		
		# remove paging
		$cisco->cmd("term len 0");

		# show CDP neighbors
		my @output = $cisco->cmd("sh cdp nei");
		
		my (@aps, $prevline);
		foreach my $out (@output){
			# remove lol
			chomp($out);
			
			# start processing
			if($prevline){
				# we found AP last line, but no interface
				# this line should contain the interface
				if($out =~ m/(Gig|Ten) ([0-9]+\/)?[0-9]+\/[0-9]+/){
					# interface found, add lines together
					# add to AP-array
					push(@aps, $prevline . $out);
					$prevline = undef;
					next;
				} else {
					# shouldn't happen
					$prevline = undef;
					next;
				}
			} else {
				if($out =~ m/^AP[a-f0-9]/){
					# this is first line containing an AP
					if($out =~ m/(Gig|Ten) ([0-9]+\/)?[0-9]+\/[0-9]+/){
						# AP + interface on same line
						# add to AP-array
						push(@aps, $out);
						next;
					} else {
						$prevline = $out;
						next;
					}
				} else {
					next;
				}
			}
		}
		
		# extract only AP-name
		foreach my $ap (@aps){
			chomp($ap);
			my $port;
			$ap =~ m/^(\S+?)\s*?((Gig|Ten) ([0-9]+\/)?[0-9]+\/[0-9]+).*?$/;
			($ap, $port) = ($1, $2);
			$port =~ s/\s//g;
			
			# Make MAC based on AP name
			(my $mac = $ap) =~ s/^AP(.+)(\.ihelse.+)?$/$1/;
			$mac = $aplol->proper_mac($mac);
			
			# Add info to hash
			$sw_aps{$mac}{name} = $ap;
			$sw_aps{$mac}{sw_port} = $port;
			$sw_aps{$mac}{sw_name} = $hostname;
			$sw_aps{$mac}{sw_ip} = $ip;
		}
		
	} else {
		# switch not available
		log_it("Switch ($hostname) not reachable.");
		next;
	}
}

# Iterate through all APs from CSV
my $csv = Text::CSV->new ( { binary => 1 } )
	or die(error_log("Cannot use CSV: " . Text::CSV->error_diag ()));

# Use custom separator
if($csv_sep){
	$csv->sep_char($csv_sep);
}

# We use File:BOM because Microsoft :-|
open_bom(my $CSV_FILE, $ap_csv, ':utf8')
	or die(error_log("Could not open file '$ap_csv': $!"));

# Assume column names is the first row
$csv->column_names($csv->getline($CSV_FILE));

while (my $row = $csv->getline_hr($CSV_FILE)){
	next unless($row->{building_name});
	# $row->{building_name}
	# $row->{floor_number}
	# $row->{ap_number}
	# $row->{ap_mac}
	# $row->{circuit_id}
	# $row->{ap_rotation}
	# $row->{comment}
	
	# Check if valid MAC
	my $apmac = $aplol->proper_mac($row->{ap_mac});
	if($aplol->valid_mac($apmac)){
		if($pi_aps->{$apmac}){
			# Valid MAC & online in Prime
			print(colored("ap_number $row->{ap_number}: Valid MAC & online\n", 'green'));
		} else {
			# Valid MAC but not online in Prime
			if($sw_aps{$apmac}){
				# Valid MAC, not online in Prime, but found on switch
				print(colored("ap_number $row->{ap_number}: Valid MAC, offline, but found on switch\n", 'cyan'));
			} else {
				# Valid MAC, and not online in either Prime or on switch
				print(colored("ap_number $row->{ap_number}: Valid MAC, offline, not found on switch\n", 'red'));
			}
		}
	} else {
		# Invalid MAC
		print(colored("ap_number $row->{ap_number}: Invalid MAC\n", 'red'));
	}
}
$csv->eof or error_log("Something went wrong: " . $csv->error_diag());
close $CSV_FILE;
 

$aplol->disconnect();


__DATA__
Do not remove. Makes sure flock() code above works as it should.
