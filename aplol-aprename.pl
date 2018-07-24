#!/usr/bin/perl
use warnings;
use strict;
use Getopt::Long;
use Net::SNMP;
use Net::SNMP::Util;
use Fcntl qw(:flock);

# Renames APs on WLCs
# Several modes are available
#
# --period
# Replace period with hyphen
# Done to avoid issues with Microsoft DNS, where each subzone
# needs to be created beforehand, and the periods in the default
# AP names is treated as zones. Command applied to the WLCs defined
# by '--dmz' or '--all'.
#
# --name
# Rename APs to "AP1122-3344-5566" naming scheme (default).
# Done regardless of what names the APs have from before.
# Command applied to the WLCs defined by '--dmz' or '--all'.
#
# --dmz
# Apply parameters to DMZ WLCs only.
#
# --all
# Apply parameters to all WLCs.


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
	
        # http://snmp.cloudapps.cisco.com/Support/SNMP/do/BrowseOID.do?local=en&translate=Translate&objectInput=1.3.6.1.4.1.9.9.513.1.1.1.1.2#oidContent
        # "This object represents the Ethernet MAC address of
        # the AP."
        'cLApIfMacAddress' => '1.3.6.1.4.1.9.9.513.1.1.1.1.2',
);

# Convert SNMP-version of MAC-address, into IEEE-version
# Input looks like "0x0013d3c4a966" (without the quotes)
sub mac_snmp_to_hex{
	my $snmp_mac = "@_";
	
	return join(':', ($snmp_mac =~ m/(?:0x)?(\w{2})/g));
}

# Check if valid AP-name
sub valid_apname{
        my ($separator, $apname) = @_;
        my $valid = 0;
        
        if($apname =~ m/^AP([a-f0-9]{4}($separator)){2}[a-f0-9]{4}$/){
                # matching the syntax we'd like to check
                # should be either of the following;
                #       APaaaa.bbbb.cccc
                #       APaaaa-bbbb-cccc
                $valid = 1;
        }
        
        return $valid;
}

# Find broken MAC
sub find_broken_mac{
        # sometimes Net::SNMP gets gibberish MAC-adresses, that should be valid
        # if that happens, we can fetch it "manually" via snmpwalk
        my ($switchip, $snmp_community, $macoid) = @_;
        
        # snmpwalk-options: -Oqv
        #   -O OUTOPTS          Toggle various defaults controlling output display:
        #       q:  quick print for easier parsing
        #       v:  print values only (not OID = value)
        my $mac = (`/usr/bin/snmpwalk -Oqv -v$config{snmp}->{version} -c$snmp_community $switchip $macoid`)[0];
        
        return "undef" unless($mac); # needs a value

	$mac = $aplol->proper_mac($mac);

        return $mac;
}

# Rename AP via SNMP
sub rename_ap{
	my ($session, $oid, $oldapname, $newapname) = @_;

	my $apoid = $oids{cLApName} . "." . $oid;

	my $write_result = $session->set_request(
		-varbindlist => [$apoid, OCTET_STRING, $newapname]
	);
	
	if(keys %$write_result){
		return 1;
	} else {
		log_it("Error: Could not set new AP-name for AP '$oldapname'.");
		return 0;
	}
}

# Rename APs if containing period
sub rename_if_period{
	my ($session, $oid, $apname) = @_;
	
	if($apname =~ m/\./){	
		(my $newapname = $apname) =~ s/\./-/g;
		
		log_it("Found AP with '.' in the name ($apname). Renaming to '$newapname'.");

		rename_ap($session, $oid, $apname, $newapname);
	}
}

# We only want 1 instance of this script running
# Check if already running -- if so, abort.
unless (flock(DATA, LOCK_EX|LOCK_NB)) {
        die("$0 is already running. Exiting.");
}

# Get options
my ($rename_period, $rename_name, $rename_dmz, $rename_all);
if (@ARGV > 0) {
	GetOptions(
		'period'	=> \$rename_period,
		'name'		=> \$rename_name,
		'dmz'		=> \$rename_dmz,
		'all'		=> \$rename_all,
	)
}

# Check if required parameters is set
unless( ($rename_period || $rename_name) &&
	($rename_dmz || $rename_all)){
	die(error_log("Required parameters not set. Exiting."));
}

$aplol->connect();
my $wlcs = $aplol->get_wlcs();
my $aps = $aplol->get_active_aps();

# iterate through all WLC's
foreach my $wlc_id (sort keys %$wlcs){
	next unless ($wlcs->{$wlc_id}{active}); # only want active WLCs
		
	if($rename_dmz){
		# only do DMZ WLCs
		next unless($wlcs->{$wlc_id}{name} =~ m/dmz/i);
	} elsif($rename_all){
		# do them all
	} else {
		die(error_log("Should not happen."));
	}

	log_it("Checking AP's on WLC '$wlcs->{$wlc_id}{name}' ($wlcs->{$wlc_id}{ipv4}).");
	
	my ($session, $error) = Net::SNMP->session(
		Hostname  => $wlcs->{$wlc_id}{ipv4},
		Community => $wlcs->{$wlc_id}{snmp_rw},
                Version   => $config{snmp}->{version},
                Timeout   => $config{snmp}->{timeout},
                Retries   => $config{snmp}->{retries},
	);

	if ($session){
		my ($result, $error) = snmpwalk(snmp => $session,
						oids => \%oids );		

		unless(keys %$result){
			error_log("Could not poll $wlcs->{$wlc_id}{name}: $error");
			$session->close();
			next;
		}

		foreach my $ap (keys %{$result->{cLApName}}){
			my $apname = $result->{cLApName}{$ap};	
			
			if($rename_period && ! $rename_name){
				# APs containing periods will be renamed if only doing $rename_period			
				rename_if_period($session, $ap, $apname);
				next;
			} elsif($rename_name){
				# rename to default name
				
				unless($result->{cLApIfMacAddress}{$ap}){
					# No MAC-address present
					# Observed on 1131 APs trying to join WLC with new software-version
					# The APs is trying to connect, but is refused due to not supported
					
					log_it("Error: No MAC found for AP '$apname'");
					
					if($rename_period){
						# We'll replace periods with hyphens at least
						rename_if_period($session, $ap, $apname);
					}
					
					# next AP at this point
					next;
				}
				
				my $ethmac = mac_snmp_to_hex($result->{cLApIfMacAddress}{$ap});
							
				# check if valid MAC
				unless($aplol->valid_mac($ethmac)){
					# try to fetch "manually"
					debug_log("Invalid MAC for AP '$apname' ($ethmac). Trying to fetch manually.");
                                        
					my $oid = $oids{cLApIfMacAddress} . "." . $ap;
					$ethmac = find_broken_mac($wlcs->{$wlc_id}{ipv4}, $wlcs->{$wlc_id}{snmp_ro}, $oid);
                                        
					unless($aplol->valid_mac($ethmac)){
						# still not a valid MAC
						# let's give up
						error_log("Error: Could not fetch proper MAC for AP '$apname': $ethmac");
						
						if($rename_period){
							# We'll replace periods with hyphens at least
							rename_if_period($session, $ap, $apname);
						}
						
						next;
					}
				}
                                
				# at this point we should have a valid MAC
				(my $propername = $ethmac) =~ s/://g;
				$propername =~ s/.{4}\K(?=.)/-/sg;
				$propername = "AP" . $propername;

                                if($apname eq $propername){
                                        # AP has proper name
                                        next;
				} else {
					# AP doesn't have proper name                            
					my $location = $aps->{$ethmac}->{location_name};
					$location = 'undef' unless($location);
					
					if(valid_apname('-', $propername)){
						# AP had wrong name, but new is OK	
						log_it("Error: AP '$apname' ($ethmac) has invalid name. Should be '$propername'. Location: $location");
						log_it("Renaming AP '$apname' to '$propername'.");
					
						next unless(rename_ap($session, $ap, $apname, $propername));
					} else {
						# AP had wrong name, and new is not OK either
						log_it("Error: AP '$apname' has invalid name. New name ($propername) is also invalid. Should not happen. Location: $location");
						
						if($rename_period){
							# We'll replace periods with hyphens at least
							rename_if_period($session, $ap, $apname);
						}
						
						next;
					}
				}
			} else {
				die(error_log("Should not happen."));
			}
		}
		
		# close after checking all AP
		$session->close();
	} else {
		error_log("Could not connect to $wlcs->{$wlc_id}{name}: $error");
		$session->close();
		next;
	}
}

$aplol->disconnect();

__DATA__
Do not remove. Makes sure flock() code above works as it should.
