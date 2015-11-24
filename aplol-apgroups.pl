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
	$aplol->log_it("apgroups", "@_");
}

# Logs debug-stuff if debug has been turned on
sub debug_log{
	$aplol->debug_log("apgroups", "@_");
}

# Logs error-stuff
sub error_log{
	$aplol->error_log("apgroups", "@_");
}

# Convert SNMP-version of MAC-address, into IEEE-version
# Input looks like "0x0013d3c4a966" (without the quotes)
sub mac_snmp_to_hex{
        my $snmp_mac = "@_";
        
        return join(':', ($snmp_mac =~ m/(?:0x)?(\w{2})/g));
}

# Find broken MAC
sub find_broken_mac{
        # sometimes Net::SNMP gets gibberish MAC-adresses, that should be valid
        # if that happens, we can fetch it "manually" via snmpwalk
        my ($switchip, $macoid) = @_;
        
        # snmpwalk-options: -Oqv
        #   -O OUTOPTS          Toggle various defaults controlling output display:
        #       q:  quick print for easier parsing
        #       v:  print values only (not OID = value)
        my $mac = (`/usr/bin/snmpwalk -Oqv -v$config{snmp}->{version} -c$config{snmp}->{read} $switchip $macoid`)[0];
        
        return "undef" unless($mac); # needs a value

        # remove all non-valid characers
        # make lowercase + insert ':'
        # pad with zeroes
        ($mac = lc($mac) ) =~ s/[^0-9a-fA-F]//g;
        $mac =~ s/..\K(?=.)/:/g;
        $mac =~ s/(^|:)(?=[0-9a-fA-F](?::|$))/${1}0/g;

        return $mac;
}

# fetch all AP's and their respective AP-groups
sub update_apgroups{
        my $wlcs = $aplol->get_wlcs();

        my %oids = (
                # http://tools.cisco.com/Support/SNMP/do/BrowseOID.do?local=en&translate=Translate&objectInput=1.3.6.1.4.1.14179.2.2.1.1#oidContent
                'bsnAPEntry' => '1.3.6.1.4.1.14179.2.2.1',
        );

        # iterate through all WLC's
        foreach my $wlc_name (sort keys %$wlcs){
                log_it("Checking AP's on WLC '$wlc_name' ($wlcs->{$wlc_name}{ipv4})...");

                my ($session, $error) = Net::SNMP->session(
                        Hostname  => $wlcs->{$wlc_name}{ipv4},
                        Community => $config{snmp}->{read},
                        Version   => $config{snmp}->{version},
                        Timeout   => $config{snmp}->{timeout},
                        Retries   => $config{snmp}->{retries},
                );

                if ($session){
                        my ($result, $error) = snmpwalk(snmp => $session,
                                                        oids => \%oids );               

                        unless(keys %$result){
                                error_log("Could not poll '$wlc_name': $error");
                                $session->close();
                                next;
                        }

                        foreach my $entry (keys %{$result->{bsnAPEntry}}){
                                if ($entry =~ m/^1\.3\./){
                                        # bsnAPName
                                        # http://tools.cisco.com/Support/SNMP/do/BrowseOID.do?local=en&translate=Translate&objectInput=1.3.6.1.4.1.14179.2.2.1.1.3#oidContent
                                        (my $apoid = $entry) =~ s/^1\.3\.(.+)$/$1/;
                
                                        # bsnAPGroupVlanName
                                        # http://tools.cisco.com/Support/SNMP/do/BrowseOID.do?local=en&translate=Translate&objectInput=1.3.6.1.4.1.14179.2.2.1.1.30#oidContent
                                        my $apgroupoid = "1.30.$apoid";

                                        # bsnAPEthernetMacAddress
                                        # http://tools.cisco.com/Support/SNMP/do/BrowseOID.do?local=en&translate=Translate&objectInput=1.3.6.1.4.1.14179.2.2.1.1.33#oidContent
                                        my $apmacoid = "1.33.$apoid";

                                        my $apname = $result->{bsnAPEntry}{$entry};
                                        my $apgroup = $result->{bsnAPEntry}{$apgroupoid};
                                        my $apmac = mac_snmp_to_hex($result->{bsnAPEntry}{$apmacoid});

                                        # if we get zero value, we make sure to try manually first
                                        $apmac = "undef" unless($apmac); 

                                        unless($apgroup){
                                                error_log("No AP-group was found.");
                                                error_log("$apname") if $apname;
                                                next;
                                        }

                                        unless($apmac =~ m/^$config{regex}->{valid_mac}$/){
                                                # has to be valid, try fetch manually

                                                my $apmacoid_complete = $oids{bsnAPEntry} . "." . $apmacoid;
                                                my $fixed_mac = find_broken_mac($wlcs->{$wlc_name}{ipv4}, $apmacoid_complete);

                                                if($fixed_mac =~ m/^$config{regex}->{valid_mac}$/){
                                                        # yay, we found valid
                                                        $apmac = $fixed_mac;
                                                } else {
                                                        # nay, still invalid
                                                        error_log("Invalid MAC: $apmac / $fixed_mac ($apname)");
                                                        next;
                                                }
                                        }

                                        my $apgroupoid_complete = $oids{bsnAPEntry} . "." . $apgroupoid;

                                        # update DB
                                        $aplol->update_apgroup_info($apmac, $apgroup, $apgroupoid_complete);
                                        debug_log("$apmac, $apgroup, $apgroupoid_complete");
                                }
                        }

                        # close after checking all AP
                        $session->close();
                } else {
                        error_log("Could not connect to '$wlc_name': $error");
                        $session->close();
                        next;
                }
        }
}


# We only want 1 instance of this script running
# Check if already running -- if so, abort.
unless (flock(DATA, LOCK_EX|LOCK_NB)) {
	die("$0 is already running. Exiting.");
}

# connect
$aplol->connect();

# apgroups
update_apgroups();

# disconnect
$aplol->disconnect();


__DATA__
Do not remove. Makes sure flock() code above works as it should.
