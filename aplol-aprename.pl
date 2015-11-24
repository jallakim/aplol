#!/usr/bin/perl
use warnings;
use strict;
use Net::SNMP;
use Net::SNMP::Util;
use Fcntl qw(:flock);

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
	$aplol->log_it("aprename", "@_");
}

# Logs debug-stuff if debug has been turned on
sub debug_log{
	$aplol->debug_log("aprename", "@_");
}

# Logs error-stuff
sub error_log{
	$aplol->error_log("aprename", "@_");
}

# variables
my %oids = (
	# http://tools.cisco.com/Support/SNMP/do/BrowseOID.do?objectInput=cLApName&translate=Translate&submitValue=SUBMIT&submitClicked=true
	# "This object represents the administrative name
	# assigned to the AP by the user. If an AP is not configured, 
	# its factory default name will be ap: of MACAddress> eg. ap:af:12:be."
	'cLApName' => '1.3.6.1.4.1.9.9.513.1.1.1.1.5',
);

# We only want 1 instance of this script running
# Check if already running -- if so, abort.
unless (flock(DATA, LOCK_EX|LOCK_NB)) {
        die("$0 is already running. Exiting.");
}

$aplol->connect();
my $wlcs = $aplol->get_wlcs();

# iterate through all WLC's
foreach my $wlc_name (sort keys %$wlcs){
	if($wlc_name =~ m/(b$|dmz)/i){ # skip dmz + ending with 'b' (HA-modules)
		log_it("Skipping WLC '$wlc_name' ($wlcs->{$wlc_name}{ipv4}).");
		next;
	} else {
		log_it("Checking AP's on WLC '$wlc_name' ($wlcs->{$wlc_name}{ipv4}).");
	}
	
	my ($session, $error) = Net::SNMP->session(
		Hostname  => $wlcs->{$wlc_name}{ipv4},
		Community => $config{snmp}->{write},
                Version   => $config{snmp}->{version},
                Timeout   => $config{snmp}->{timeout},
                Retries   => $config{snmp}->{retries},
	);

	if ($session){
		my ($result, $error) = snmpwalk(snmp => $session,
						oids => \%oids );		

		unless(keys %$result){
			error_log("Could not poll $wlc_name: $error");
			$session->close();
			next;
		}

		foreach my $ap (keys %{$result->{cLApName}}){
			my $apname = $result->{cLApName}{$ap};
			if ($apname =~ m/\./g){
				# if AP have . in the name
				(my $newapname = $apname) =~ s/\./-/g;
				
				debug_log("Found AP with '.' in the name ($apname). Renaming to '$newapname'.");

				my $apoid = $oids{cLApName} . "." . $ap;
		
				my $write_result = $session->set_request(
					-varbindlist => [$apoid, OCTET_STRING, $newapname]
				);
				
				unless (keys %$write_result){
					error_log("Could not set new AP-name for ap '$apname'.");
					next;
				}	
			}
		}
		
		# close after checking all AP
		$session->close();
	} else {
		error_log("Could not connect to $wlc_name: $error");
		$session->close();
		next;
	}
}

$aplol->disconnect();

__DATA__
Do not remove. Makes sure flock() code above works as it should.
