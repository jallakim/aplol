#!/usr/bin/perl
# From command-line;
#     https_proxy= HTTPS_PROXY= perl aplol-ciscopi-aps.pl
use warnings;
use strict;
use POSIX qw(strftime);
use POSIX qw(floor);
use JSON -support_by_pp;
use LWP 5.64;
use LWP::UserAgent;
use Net::SSL; # needed, else LWP goes into emo-mode
use Fcntl qw(:flock);
use Try::Tiny;
use Date::Parse;
use Scalar::Util qw/reftype/;
binmode(STDOUT, ":utf8");

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
my (%locations, $root_aps);

# Log
sub log_it{
	$aplol->log_it("ciscopi-aps", "@_");
}

# Logs debug-stuff if debug has been turned on
sub debug_log{
	$aplol->debug_log("ciscopi-aps", "@_");
}

# Logs error-stuff
sub error_log{
	$aplol->error_log("ciscopi-aps", "@_");
}

# fetch PI API content
sub get_url{
        my $url = shift;
        my $full_url = $config{ciscopi}->{baseurl} . "/" . $url;

	$ENV{PERL_LWP_SSL_VERIFY_HOSTNAME} = 0; # just to be sure :-D
	my $ua = LWP::UserAgent->new(proxy => '');
	my $req = HTTP::Request->new(GET => $full_url);
	$req->authorization_basic($config{ciscopi}->{username}, $config{ciscopi}->{password});

	return $ua->request($req)->content();
}

# get JSON from PI
sub get_json{
	my $url = shift;
	my $json = new JSON;
	my $newurl = $url;
	my @json_content;

	while(1){
		# iterate through all pagings until done
		my $url_content = get_url($newurl);
	
		if($url_content){
			my $json_text;
			try {
				$json_text = $json->allow_nonref->utf8->relaxed->escape_slash->loose->allow_singlequote->allow_barekey->decode($url_content);
			} catch {
				use Data::Dumper;
				print Dumper($url_content);
				die(error_log("Malformed output from \$url_content; '$url'"));
			};
			
			my $first = $json_text->{queryResponse}->{'@first'};
			my $last = $json_text->{queryResponse}->{'@last'};
			my $count = $json_text->{queryResponse}->{'@count'};
			
			if($count == 0){
				# no APs found
				return [];
			} elsif(($last + 1) == $count){
				# this is last page
				push(@json_content, @{$json_text->{queryResponse}->{'entity'}});
				last;
			} elsif(($last + 1) < $count){
				# more pages
				push(@json_content, @{$json_text->{queryResponse}->{'entity'}});
				$newurl = $url . "&.firstResult=" . ($last + 1);
				next;
			} else {
				die(error_log("Wrong 'first' and 'count' in JSON."));
			}
		} else {
			die(error_log("No content returned from get_url()."));
		}
	}
	
	return \@json_content;
}

# fetch AP info
sub get_apinfo{
	my $vd = shift;
	my $url = "data/AccessPointDetails.json?.full=true&type=\"UnifiedAp\"&_ctx.domain=$vd";
        return get_json($url);
}

# fetch alarm info
sub get_alarminfo{
        my $severity = shift;
	my $url = "data/Alarms.json?.full=true&severity=$severity&acknowledgementStatus=false&_ctx.domain=ROOT-DOMAIN";
        return get_json($url);
}

# fetch all APs
sub get_aps{
	my $vd = shift;
	$vd = "ROOT-DOMAIN" unless($vd);
	my $pi_aps = get_apinfo($vd);
	my %aps;
	
	if($pi_aps){
		foreach my $apinfo (@$pi_aps){
			# neighbor stuff
			my $neighbor_count = keys %{$apinfo->{'accessPointDetailsDTO'}->{'cdpNeighbors'}->{'cdpNeighbor'}};
			my ($neighbor_name, $neighbor_addr, $neighbor_port);
			if($neighbor_count == 0){
				$neighbor_name = '';
				$neighbor_addr = "0.0.0.0";
				$neighbor_port = '';
			} else {
				$neighbor_name = $apinfo->{'accessPointDetailsDTO'}->{'cdpNeighbors'}->{'cdpNeighbor'}->{'neighborName'};
				$neighbor_addr = $apinfo->{'accessPointDetailsDTO'}->{'cdpNeighbors'}->{'cdpNeighbor'}->{'neighborIpAddress'};
				$neighbor_port = $apinfo->{'accessPointDetailsDTO'}->{'cdpNeighbors'}->{'cdpNeighbor'}->{'neighborPort'};

				# remove whitespace from IP
				$neighbor_addr =~ s/\s//g;

				# remove domain from hostname
				$neighbor_name =~ s/^(.+?)\..*/$1/;

				# short portname
				$neighbor_port =~ s/GigabitEthernet/Gi/;
				$neighbor_port =~ s/FastEthernet/Fa/;
			}

			# online/offline?
			my $associated = 0;
			if( $apinfo->{'accessPointDetailsDTO'}->{'reachabilityStatus'} =~ m/^Reachable$/ ){
				$associated = 1;
			}
			
			# controller -- not present if AP is unassociated
			my $controller = "unassociated";
			if( $apinfo->{'accessPointDetailsDTO'}->{'unifiedApInfo'}->{'controllerName'} ){
				$controller = $apinfo->{'accessPointDetailsDTO'}->{'unifiedApInfo'}->{'controllerName'};
			}

			# uptime
			my $uptime = $apinfo->{'accessPointDetailsDTO'}->{'upTime'};
			$uptime = 0 unless($uptime);
			
			# weird scenario with a malformed AP entry
			unless($apinfo->{'accessPointDetailsDTO'}->{'name'}){
				use Data::Dumper;
				print Dumper($apinfo);
				die(error_log("Malformed AP."));
			}

			# all variables should be ready
			my %ap = (
				name => $apinfo->{'accessPointDetailsDTO'}->{'name'},
				ethmac => $apinfo->{'accessPointDetailsDTO'}->{'ethernetMac'},
				wmac => $apinfo->{'accessPointDetailsDTO'}->{'macAddress'},
				serial => $apinfo->{'accessPointDetailsDTO'}->{'serialNumber'},
				ip => $apinfo->{'accessPointDetailsDTO'}->{'ipAddress'},
				model => $apinfo->{'accessPointDetailsDTO'}->{'model'},
				location => $apinfo->{'accessPointDetailsDTO'}->{'locationHeirarchy'},
				controller => $controller,
				associated => $associated,
				uptime => $uptime,
				neighbor_name => $neighbor_name,
				neighbor_addr => $neighbor_addr,
				neighbor_port => $neighbor_port,
				client_total => $apinfo->{'accessPointDetailsDTO'}->{'clientCount'},
				client_24 => $apinfo->{'accessPointDetailsDTO'}->{'clientCount_2_4GHz'},
				client_5 => $apinfo->{'accessPointDetailsDTO'}->{'clientCount_5GHz'},
			);

			# add info
			$aps{$ap{ethmac}} = \%ap unless $aps{$ap{ethmac}};
			
			# add VD for this location
			unless ($locations{$ap{location}}){
				$locations{$ap{location}} = [];
			}
			unless ($aplol->array_contains($locations{$ap{location}}, $vd)){
				push(@{$locations{$ap{location}}}, $vd);
			}
		}
	}
	
	return \%aps;
}

# update all APs
sub update_from_prime{
	my $db_vds = $aplol->get_vds();

	# iterate through all VDs
	# TODO: update DB with available VDs,
	# (not possible until this info is available via PI API)
	# (for now, we have to maintain the VDs in the DB manually)
	foreach my $vd (keys %$db_vds){
		my $aps = get_aps($vd);
		
		if($vd =~ m/^ROOT-DOMAIN$/){
			# all APs -- this is the authorative source
			$root_aps = $aps;			
		}
		
		# PI is emo, wait a bit
		sleep(5);
	}
	
	# at this point we should have all locations
	# and what VDs they belong to	
	# iterate through locations, add/remove, fix mapping
	update_locations();
	
	# now all locations should be up to date
	# now we can add/deactivate/update APs
	update_aps();
}

# update all locations in DB
sub update_locations{
	# get all locations from DB
	my $db_locations = $aplol->get_locations();
	
	# delete all entries present in both lists
	foreach my $location (keys %locations){
		if($db_locations->{$location}){
			# update VD's for this location in DB
			update_location($location);
						
			# delete from both
			delete($locations{$location});
                        delete($db_locations->{$location});
		}
	}
		
	# then delete everything from DB that 
	# only has an entry in the DB
	foreach my $location (keys %$db_locations){
		$aplol->delete_location($db_locations->{$location}{id});
	}
	
	# then add everything to DB that has
	# an entry in the report list
	foreach my $location (keys %locations){
		
		# add location
		$aplol->add_location($location);
		
		# add VD <-> location mapping
		foreach my $vd (@{$locations{$location}}){
			$aplol->add_location_vd($vd, $location);
		}
	}
}

# update all VD's for a specific location
sub update_location{
	my $location = "@_";
	
	# get all current VD's for location
	my $db_location_vds = $aplol->get_location_vds($location);

	# check with current VD's
	my %location_vds = map { $_ => 1 } @{$locations{$location}};
	
	foreach my $vd (keys %location_vds){
		if($db_location_vds->{$vd}){
			# delete from both
			delete($location_vds{$vd});
			delete($db_location_vds->{$vd});
		}
	}
			
	# delete from DB if only present in DB
	foreach my $vd (keys %$db_location_vds){
		$aplol->delete_location_vd($db_location_vds->{$vd}{vd_id}, $db_location_vds->{$vd}{location_id});
	}
	
	# add to DB if not present
	foreach my $vd (keys %location_vds){
		$aplol->add_location_vd($vd, $location);
	}
}

# update all AP's
sub update_aps{
	my $wlcs = $aplol->get_wlcs();
	my $db_aps = $aplol->get_aps();
	
	foreach my $ethmac (sort keys %$root_aps){
		if($db_aps->{$ethmac}){
			# update AP-info
			update_ap($wlcs, $ethmac);
						
			# delete from both
			delete($root_aps->{$ethmac});
                        delete($db_aps->{$ethmac});
		}
	}
		
	# deactivate if only present in DB
	foreach my $ethmac (keys %$db_aps){
		$aplol->deactivate_ap($ethmac);
	}
	
	# add to DB if not present
	foreach my $ethmac (keys %$root_aps){
		my $wlc_id = get_wlc_id($wlcs, $ethmac);
		unless(defined($wlc_id)){
			error_log("Controller '$root_aps->{$ethmac}{controller}' does not exist in DB. Please fix.");
			next;
		}
		
		my $location_id = get_location_id($ethmac);
		unless(defined($location_id)){
			error_log("Location '$root_aps->{$ethmac}{location}' does not exist in DB. Please fix.");
			next;
		}
				
		# at this point we should have valid $wlc_id and $location_id
		$root_aps->{$ethmac}{wlc_id} = $wlc_id;
		$root_aps->{$ethmac}{location_id} = $location_id;
		
		$aplol->add_ap($root_aps->{$ethmac});
	}
}

# find WLC ID, if associated
sub get_wlc_id{
	my ($wlcs, $ethmac) = @_;
	
	my $wlc_id;
	if ($root_aps->{$ethmac}{controller} =~ m/^unassociated$/){
		# not associated
		$wlc_id = '0';
	} else {
		# associated	
		if ($wlcs->{$root_aps->{$ethmac}{controller}}){
			# controller exists in DB
			$wlc_id = $wlcs->{$root_aps->{$ethmac}{controller}}{id};
		} else {
			# does not exist, should only happen if we forgot to add new controllers
			$wlc_id = undef;
		}
	}
	
	return $wlc_id;
}

# find location ID
sub get_location_id{
	my $ethmac = "@_";
	
	my $location_id;
	my $location_item = $aplol->get_location($root_aps->{$ethmac}{location});
	
	if($location_item){
		$location_id = $location_item->{id};
	} else {
		$location_id = undef;
	}
	
	return $location_id;
}

# update AP-info
# reports are always authorative
sub update_ap{
	my ($wlcs, $ethmac) = @_;
	
	my $wlc_id = get_wlc_id($wlcs, $ethmac);
	unless(defined($wlc_id)){
		error_log("Controller '$root_aps->{$ethmac}{controller}' does not exist in DB. Please fix.");
		return;
	}
	
	my $location_id = get_location_id($ethmac);
	unless(defined($location_id)){
		error_log("Location '$root_aps->{$ethmac}{location}' does not exist in DB. Please fix.");
		return;
	}
				
	# at this point we should have valid $wlc_id and $location_id
	$root_aps->{$ethmac}{wlc_id} = $wlc_id;
	$root_aps->{$ethmac}{location_id} = $location_id;
	
	$aplol->update_ap($root_aps->{$ethmac});
}

# get all alarms
sub update_alarms{
	my $severity = 'CRITICAL';
	my $alarms = get_alarminfo($severity);

	if($alarms){
                # reset all alarms (so we don't get old in DB)
                $aplol->reset_alarms();

        	foreach my $alarm (@$alarms){
                        if($alarm->{'alarmsDTO'}->{'category'}->{'value'} =~ m/^AP$/){
                                # Alarm-type is AP

                                # get last annotation
                                my ($alarm_annotation, $alarm_timestamp) = get_last_alarm_annotation($alarm->{'alarmsDTO'}->{'annotations'});
				if($alarm_annotation =~ m/^[0-9]+$/){
					# only if numbers
					$alarm_annotation =~ s/\s+//;
				} else {
					# not just numbers, short it down to max 10 chars
					$alarm_annotation = substr($alarm_annotation, 0, 10);
				}

                                # get ap-name
                                my $wmac = (split(',', $alarm->{'alarmsDTO'}->{'deviceName'}))[1];
                                next unless($wmac);
                                
				if(floor(str2time($alarm_timestamp)) > floor(str2time($alarm->{'alarmsDTO'}->{'lastUpdatedAt'}))){
					# only if annotation was created after alarm was updated
					# lets update DB
					debug_log("update alarm: $wmac, $alarm_annotation");
					$aplol->update_alarm($wmac, $alarm_annotation);
				}
                        }
                }
	}
}

# fetch latest annotation
sub get_last_alarm_annotation{
        my $annotations = shift;

        if(defined($annotations)){		
                foreach my $annotation_info (values %$annotations){
                        # $annotation_info is hash if only 1 value
                        # if multiple values, it's array of hashes
                        
                        if (reftype $annotation_info eq reftype {}) {
                                # hash, should be single value
                                # just return noteText
                                return ($annotation_info->{'noteText'}, $annotation_info->{'creationTimestamp'});
                        } else {
                                # assume array of hashes
                                # sort it first, and then pick most recent date

                                my @sorted = sort {     str2time($b->{'creationTimestamp'}) <=>
                                                        str2time($a->{'creationTimestamp'})}
                                                        @$annotation_info;

                                return ($sorted[0]->{'noteText'}, $sorted[0]->{'creationTimestamp'});
                        }
                }
        } else {
                # no annotations
                return ("undef", "1999-01-01 12:00:00");
        }
}


# We only want 1 instance of this script running
# Check if already running -- if so, abort.
unless (flock(DATA, LOCK_EX|LOCK_NB)) {
	die("$0 is already running. Exiting.");
}

# connect
$aplol->connect();

# update info from PI
# add/delete locations
# add/update/delete location<->VD mapping
# add/deactivate/update APs
update_from_prime();

# update/set alarm annotations
update_alarms();

# disconnect
$aplol->disconnect();


__DATA__
Do not remove. Makes sure flock() code above works as it should.