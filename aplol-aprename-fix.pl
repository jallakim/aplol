#!/usr/bin/perl
use warnings;
use strict;
use Net::SNMP;
use Net::SNMP::Util;
use Fcntl qw(:flock);

# Finds "broken" AP-names (wrong MAC address or similar)

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
	$aplol->log_it("aprename-fix", "@_");
}

# Logs debug-stuff if debug has been turned on
sub debug_log{
	$aplol->debug_log("aprename-fix", "@_");
}

# Logs error-stuff
sub error_log{
	$aplol->error_log("aprename-fix", "@_");
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

# We only want 1 instance of this script running
# Check if already running -- if so, abort.
unless (flock(DATA, LOCK_EX|LOCK_NB)) {
        die("$0 is already running. Exiting.");
}

# Convert SNMP-version of MAC-address, into IEEE-version
# Input looks like "0x0013d3c4a966" (without the quotes)
sub mac_snmp_to_hex{
	my $snmp_mac = "@_";
	
	return join(':', ($snmp_mac =~ m/(?:0x)?(\w{2})/g));
}

# Check if valid AP-name
sub valid_apname{
        my $apname = "@_";
        my $valid = 0;
        
        if($apname =~ m/^AP([a-f0-9]{4}(\.|-)){2}[a-f0-9]{4}$/){
                # matching the syntax we'd like to check
                # should be either of the following;
                #       APaaaa.bbbb.cccc
                #       APaaaa-bbbb-cccc
                # done to ensure that we don't "fix" specially named APs
                $valid = 1;
        }
        
        return $valid;
}

# Check if valid MAC
sub valid_mac{
        my $mac = "@_";
        my $valid = 0;
        
        if($mac =~ m/^([0-9a-f]{2}[:-]){5}([0-9a-f]{2})$/i){
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

        # remove all non-valid characers
        # make lowercase + insert ':'
        # pad with zeroes
        ($mac = lc($mac) ) =~ s/[^0-9a-fA-F]//g;
        $mac =~ s/..\K(?=.)/:/g;
        $mac =~ s/(^|:)(?=[0-9a-fA-F](?::|$))/${1}0/g;

        return $mac;
}

$aplol->connect();
my $wlcs = $aplol->get_wlcs();
my $aps = $aplol->get_active_aps();

# iterate through all WLC's
foreach my $wlc_id (sort keys %$wlcs){
	next if ($wlcs->{$wlc_id}{name} =~ m/dmz/i); # skip dmz
	next unless ($wlcs->{$wlc_id}{active}); # only want active WLCs

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
			
			unless($result->{cLApIfMacAddress}{$ap}){
				# No MAC-address present
				# Observed on 1131 APs trying to join WLC with new software-version
				# The APs is trying to connect, but is refused due to not supported
				error_log("No MAC found for AP '$apname'");
				next;
			}

                        my $ethmac = mac_snmp_to_hex($result->{cLApIfMacAddress}{$ap});
                        
                        if(valid_apname($apname)){
                                # valid AP-name
                                # check if valid MAC
                                unless(valid_mac($ethmac)){
                                        # try to fetch "manually"
                                        debug_log("Invalid MAC for AP '$apname' ($ethmac). Trying to fetch manually.");
                                        
                                        my $oid = $oids{cLApIfMacAddress} . "." . $ap;
                                        $ethmac = find_broken_mac($wlcs->{$wlc_id}{ipv4}, $wlcs->{$wlc_id}{snmp_ro}, $oid);
                                        
                                        unless(valid_mac($ethmac)){
                                                # still not a valid MAC
                                                # let's give up
                                                error_log("Could not fetch proper MAC for AP '$apname': $ethmac");
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
                                        # AP has mismatched AP-name
                                        error_log("AP '$apname' ($ethmac) has invalid name. Should be '$propername'. Location: $aps->{$ethmac}->{location_name}");
                                        log_it("Renaming AP '$apname' to '$propername'.");
                                        
                                        my $apoid = $oids{cLApName} . "." . $ap;

                                        my $write_result = $session->set_request(
                                               -varbindlist => [$apoid, OCTET_STRING, $propername]
                                        );

                                        unless (keys %$write_result){
                                               error_log("Could not set new AP-name for ap '$apname'.");
                                               next;
                                        }
                                }
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
