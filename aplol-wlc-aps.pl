#!/usr/bin/perl
use warnings;
use strict;
use Net::SNMP;
use Net::SNMP::Util;
use Fcntl qw(:flock);

# Gathers information from the WLCs directly, and correalates this
# with the information within Cisco Prime
# Done as a sanity check that the information within Prime is OK

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
my ($wlc_aps, $db_aps, $diff_aps);

# Log
sub log_it{
	$aplol->log_it("wlc", "@_");
}

# Logs debug-stuff if debug has been turned on
sub debug_log{
	$aplol->debug_log("wlc", "@_");
}

# Logs error-stuff
sub error_log{
	$aplol->error_log("wlc", "@_");
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

# fetch all AP's and their respective AP-groups
sub update_apgroups{
        my $wlcs = $aplol->get_wlcs();

        my %oids = (
                # http://tools.cisco.com/Support/SNMP/do/BrowseOID.do?local=en&translate=Translate&objectInput=1.3.6.1.4.1.14179.2.2.1.1#oidContent
                'bsnAPEntry' => '1.3.6.1.4.1.14179.2.2.1',
        );

        # iterate through all WLC's
        foreach my $wlc_id (sort keys %$wlcs){
		next unless ($wlcs->{$wlc_id}{active}); # only want active WLCs

                log_it("Checking AP's on WLC '$wlcs->{$wlc_id}{name}' ($wlcs->{$wlc_id}{ipv4})...");

                my ($session, $error) = Net::SNMP->session(
                        Hostname  => $wlcs->{$wlc_id}{ipv4},
                        Community => $wlcs->{$wlc_id}{snmp_ro},
                        Version   => $config{snmp}->{version},
                        Timeout   => $config{snmp}->{timeout},
                        Retries   => $config{snmp}->{retries},
                );

                if ($session){
                        my ($result, $error) = snmpwalk(snmp => $session,
                                                        oids => \%oids );

                        unless(keys %$result){
                                error_log("Could not poll '$wlcs->{$wlc_id}{name}': $error");
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

                                        unless($aplol->valid_mac($apmac)){
                                                # has to be valid, try fetch manually

                                                my $apmacoid_complete = $oids{bsnAPEntry} . "." . $apmacoid;
                                                my $fixed_mac = find_broken_mac($wlcs->{$wlc_id}{ipv4}, $wlcs->{$wlc_id}{snmp_ro}, $apmacoid_complete);

                                                if($aplol->valid_mac($fixed_mac)){
                                                        # yay, we found valid
                                                        $apmac = $fixed_mac;
                                                } else {
                                                        # nay, still invalid
                                                        error_log("Invalid MAC: $apmac / $fixed_mac ($apname)");
                                                        next;
                                                }
                                        }

                                        my $apgroupoid_complete = $oids{bsnAPEntry} . "." . $apgroupoid;

                                        # add to WLC-hash
					$wlc_aps->{$apmac}{name} = $apname;
					$wlc_aps->{$apmac}{wlc_apgroup} = $apgroup;
					$wlc_aps->{$apmac}{wlc_name} = $wlcs->{$wlc_id}{name};				
					
					# update DB
                                        $aplol->update_apgroup_info($apmac, $apgroup);
                                        debug_log("$apmac, $apgroup, $apgroupoid_complete");
                                }
                        }

                        # close after checking all AP
                        $session->close();
                } else {
                        error_log("Could not connect to '$wlcs->{$wlc_id}{name}': $error");
                        $session->close();
                        next;
                }
        }
}

sub compare_wlc_prime{
	# fetch all AP's from DB
	$db_aps = $aplol->get_active_aps();
	
	foreach my $ethmac (sort keys %$db_aps){
		if($wlc_aps->{$ethmac}){
			# found on a WLC, check values
			
			my $match = 1;
			unless($db_aps->{$ethmac}{wlc_name} =~ m/^$wlc_aps->{$ethmac}{wlc_name}$/){
				# not a match
				$match = 0;
			}
			
			unless($db_aps->{$ethmac}{apgroup_name} =~ m/^$wlc_aps->{$ethmac}{wlc_apgroup}$/){
				# not a match
				$match = 0;
			}
			
			unless($match){
				# non-identical entry, add to hash
				
				# set values from WLC
				$diff_aps->{$ethmac}{name} = $wlc_aps->{$ethmac}{name};
				$diff_aps->{$ethmac}{wlc_apgroup} = $wlc_aps->{$ethmac}{wlc_apgroup};
				$diff_aps->{$ethmac}{wlc_name} = $wlc_aps->{$ethmac}{wlc_name};
				
				# set values from DB
				$diff_aps->{$ethmac}{db_wlc_name} = $db_aps->{$ethmac}{wlc_name};
				$diff_aps->{$ethmac}{db_wlc_name} = "undef" unless($diff_aps->{$ethmac}{db_wlc_name});
				$diff_aps->{$ethmac}{db_apgroup} = $db_aps->{$ethmac}{apgroup_name};
				$diff_aps->{$ethmac}{db_apgroup} = "undef" unless($diff_aps->{$ethmac}{db_apgroup});
			}
		} else {
			# could happen if AP is disassociated with WLC
			# entry is not identical, so we can just assume it's offline, and add relevant info
			
			$diff_aps->{$ethmac}{name} = $db_aps->{$ethmac}{name};
			$diff_aps->{$ethmac}{wlc_apgroup} = "undef";
			$diff_aps->{$ethmac}{wlc_name} = "unassociated";
			
			# set values from DB
			$diff_aps->{$ethmac}{db_wlc_name} = $db_aps->{$ethmac}{wlc_name};
			$diff_aps->{$ethmac}{db_apgroup} = $db_aps->{$ethmac}{apgroup_name};
		}
	}
	
	# empty the aps_diff table
	# we could just update whatever is there, but, bleh
	$aplol->empty_aps_diff();
	
	# at this point, $wlc_aps should contain all AP's that are
	# 1) not equal to PI regarding associated WLC and/or wrong AP-group
	# 2) not present at all on PI
	# 3) present in PI, but not on WLC (offline, but online in Prime)
	foreach my $ethmac (sort keys %$diff_aps){
		
		if(	($diff_aps->{$ethmac}{wlc_name} =~ m/^unassociated$/) &&
			($diff_aps->{$ethmac}{db_wlc_name} =~ m/^unassociated$/)){
			# AP is unassociated on both systems
			# we don't want to list these, as these are legit
			next;
		}

		$aplol->add_aps_diff(	$ethmac,
					$diff_aps->{$ethmac}{name},
					$diff_aps->{$ethmac}{wlc_apgroup},
					$diff_aps->{$ethmac}{db_apgroup},
					$diff_aps->{$ethmac}{wlc_name},
					$diff_aps->{$ethmac}{db_wlc_name});
	}
}


# We only want 1 instance of this script running
# Check if already running -- if so, abort.
unless (flock(DATA, LOCK_EX|LOCK_NB)) {
	die("$0 is already running. Exiting.");
}

# connect
my $time_start = time(); # set start time
$aplol->connect();

# apgroups
update_apgroups();

# compare info from PI and WLC
# should reveal AP's within PI that has wrong AP-group or WLC-association
# it should also find AP's that are not yet discovered by PI
compare_wlc_prime();

# disconnect
$aplol->disconnect();

# How long did we run for?
my $runtime = time() - $time_start;
log_it("Took $runtime seconds to complete.");


__DATA__
Do not remove. Makes sure flock() code above works as it should.
