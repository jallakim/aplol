#!/usr/bin/perl
use warnings;
use strict;
use CGI;
use JSON;
use Time::Local;
use POSIX qw(strftime);
use POSIX qw(floor);
use Date::Parse;

# Load aplol
my $aplol_dir;
BEGIN {
	use FindBin;
	$aplol_dir = "$FindBin::Bin/../.."; # Assume two levels up from working-folder
}
use lib $aplol_dir;
use aplol;
my $aplol = aplol->new({ disable_log => 'true' }); # disable log
my %config = $aplol->get_config();

# return 200 OK
sub header{
	return CGI::header(
		-type => 'text/plain',
		-status => '200',
		-charset => 'utf-8'
	);
}

# return unique portnumber
sub port_number{
	my $port = "@_";

	# fetch linecard + port number
        my $chassis = 1;
        my ($linecard, $port_number);
        if($port =~ m,^[a-zA-Z]+(\d+)/(\d+)$,){
        	# interface linecard/port
                ($linecard, $port_number) = ($1, $2);
        } elsif ($port =~ m,^[a-zA-Z]+(\d+)/(\d+)/(\d+)$,){
        	# interface chassis/linecard/port
                ($chassis, $linecard, $port_number) = ($1, $2, $3);
        } else {
                # unknown port
                ($linecard, $port_number) = (1, 1);
        }

	$linecard = 1 if($linecard == 0); # Fa1/0/31

	# multiply chassis (if present) with module number, and then with 48, as this is the
        # highest port-density for a switch/module. this way we ensure that we can do a numbered
        # sort on port -- even if there are members from different modules on the same switch
        return int($chassis * ($linecard * 48) + $port_number);
}

# returns nice uptime
sub nice_uptime{
	my $uptime = shift;

	my $uptime_nice;
	if($uptime){
		# some value was returned
		# $uptime is milliseconds (!)
		$uptime = $uptime / 100; # uptime in seconds
		my $sec = $uptime % 60;
		my $min = ($uptime / 60) % 60;
		my $hours = ($uptime / 60 / 60) % 24;
		my $days = floor($uptime / 60 / 60 / 24);

		# make text
		$uptime_nice = sprintf("%02dd %02dh %02dm %02ds", $days, $hours, $min, $sec);
	} else {
		$uptime_nice = "00d 00h 00m 00s";
	}

	return $uptime_nice;
}

my $cgi = CGI->new();
my $page = $cgi->param('p');

unless($page){
	print CGI::header(
		-type => 'text/plain',
		-status => '404',
		-charset => 'utf-8'
	);
	exit 0;
}

# we have something valid, let's fetch some data
$aplol->connect();

if($page =~ m/^unassigned$/){
	## Unassigned APs
	my $aps = $aplol->get_active_aps();
	
	my @json_array;
	
	foreach my $ethmac (keys %$aps){
		
		# Skip unwanted APs
		unless (
			# We only want unassigned APs
			( $aps->{$ethmac}{location_name} =~ m/^Root Area$/ )
		){
			next;
		}
		
		my $neighbor_addr = $aps->{$ethmac}{neighbor_addr};
		$neighbor_addr = "" if $neighbor_addr =~ m/^0\.0\.0\.0$/;
		
		my @ap = (
			$aps->{$ethmac}{name},
			$aps->{$ethmac}{ip},
			$aps->{$ethmac}{model},
			$aps->{$ethmac}{wlc_name},
			nice_uptime($aps->{$ethmac}{uptime}),
			$aps->{$ethmac}{neighbor_name},
			$neighbor_addr,
			$aps->{$ethmac}{neighbor_port},
			port_number($aps->{$ethmac}{neighbor_port})
		);
		push(@json_array, \@ap);
	}
	
	my %json_data;
	$json_data{data} = \@json_array;
	my $json = encode_json \%json_data;
	
	print header();
	print $json;
	
} elsif($page =~ m/^unassociated$/){
	## Unassociated APs
	my $aps = $aplol->get_active_aps();
	
	my @json_array;
	
	foreach my $ethmac (keys %$aps){
		
		# Skip unwanted APs
		unless (
			# We only want unassociated APs
			( $aps->{$ethmac}{associated} == 0 ) &&
			
			# We don't want OEAPs
			( $aps->{$ethmac}{model} !~ m/OEAP/ ) &&
						
			# We don't want 'HBE Utlån'
			( $aps->{$ethmac}{location_name} !~ m/HBE > Utlan/ )			
		){
			next;
		}
		
		my $neighbor_addr = $aps->{$ethmac}{neighbor_addr};
		$neighbor_addr = "" if $neighbor_addr =~ m/^0\.0\.0\.0$/;

		# short timestamp
		# YYYY-MM-DD, HH:MM
		my $alarm_timestamp = POSIX::strftime(
				"%Y-%m-%d, %H:%M",
				localtime(str2time($aps->{$ethmac}{last_alarm}))
		);

		# fetch & shorten annotation
		my $alarm_annotation = $aps->{$ethmac}{alarm};
		if($alarm_annotation =~ m/^[0-9]+$/){
			# only if numbers
			$alarm_annotation =~ s/\s+//;
		} else {
			# not just numbers, short it down to max 10 chars
			$alarm_annotation = substr($alarm_annotation, 0, 10);
		}
		
		my @ap = (
			$aps->{$ethmac}{name},
			$aps->{$ethmac}{ip},
			$aps->{$ethmac}{model},
			$aps->{$ethmac}{neighbor_name},
			$neighbor_addr,
			$aps->{$ethmac}{neighbor_port},
			$aps->{$ethmac}{location_name},
			$alarm_timestamp,
			$alarm_annotation,
			port_number($aps->{$ethmac}{neighbor_port})
		);
		push(@json_array, \@ap);
	}
	
	my %json_data;
	$json_data{data} = \@json_array;
	my $json = encode_json \%json_data;
	
	print header();
	print $json;

} elsif($page =~ m/^rootdomain$/){
	## APs member of only ROOT-DOMAIN
	my $aps = $aplol->get_rootdomain_aps();
	
	my @json_array;
	
	foreach my $ethmac (keys %$aps){
		my $neighbor_addr = $aps->{$ethmac}{neighbor_addr};
		$neighbor_addr = "" if $neighbor_addr =~ m/^0\.0\.0\.0$/;
		
		my @ap = (
			$aps->{$ethmac}{name},
			$aps->{$ethmac}{ip},
			$aps->{$ethmac}{model},
			$aps->{$ethmac}{wlc_name},
			$aps->{$ethmac}{neighbor_name},
			$neighbor_addr,
			$aps->{$ethmac}{neighbor_port},
			$aps->{$ethmac}{location_name},
			port_number($aps->{$ethmac}{neighbor_port})
		);
		push(@json_array, \@ap);
	}
	
	my %json_data;
	$json_data{data} = \@json_array;
	my $json = encode_json \%json_data;
	
	print header();
	print $json;

} elsif($page =~ m/^all$/){
	## All active APs regardless of status
	my $aps = $aplol->get_active_aps();
	
	my @json_array;
	
	foreach my $ethmac (keys %$aps){
		my $neighbor_addr = $aps->{$ethmac}{neighbor_addr};
		$neighbor_addr = "" if $neighbor_addr =~ m/^0\.0\.0\.0$/;
		
		my @ap = (
			$aps->{$ethmac}{name},
			$aps->{$ethmac}{ip},
			$aps->{$ethmac}{model},
			$aps->{$ethmac}{wlc_name},
			$aps->{$ethmac}{neighbor_name},
			$neighbor_addr,
			$aps->{$ethmac}{neighbor_port},
			$aps->{$ethmac}{location_name},
			port_number($aps->{$ethmac}{neighbor_port})
		);
		push(@json_array, \@ap);
	}
	
	my %json_data;
	$json_data{data} = \@json_array;
	my $json = encode_json \%json_data;
	
	print header();
	print $json;

} elsif($page =~ m/^apgroup(default)?$/){
	## AP groups
	my $aps = $aplol->get_active_aps();
	my $default_only = 0;
	$default_only = 1 if($page =~ m/^apgroupdefault$/);
	
	my @json_array;
	
	foreach my $ethmac (keys %$aps){
		next if($aps->{$ethmac}{model} =~ m/OEAP/); # don't want OEAPs
		
		# show only default-group and deactivated, and not in Root Area
		if($default_only){
			next unless($aps->{$ethmac}{apgroup_name} =~ m/^(default-group|deaktivert)$/);
			next if($aps->{$ethmac}{location_name} =~ m/^Root Area$/);
		}

		my $neighbor_addr = $aps->{$ethmac}{neighbor_addr};
		$neighbor_addr = "" if $neighbor_addr =~ m/^0\.0\.0\.0$/;

		my $ap_name;
		if($aps->{$ethmac}{associated} && $aps->{$ethmac}{active}){
			# it's online and active
			# make HTML-link
			$ap_name = qq(<a href="/apgroup.pl?ethmac=$ethmac&action=select">$aps->{$ethmac}{name}</a>);
		} else {
			$ap_name = $aps->{$ethmac}{name};
		}
		
		my @ap = (
			$ap_name,
			$aps->{$ethmac}{ip},
			$aps->{$ethmac}{model},
			$aps->{$ethmac}{wlc_name},
			$aps->{$ethmac}{neighbor_name},
			$neighbor_addr,
			$aps->{$ethmac}{neighbor_port},
			$aps->{$ethmac}{location_name},
			$aps->{$ethmac}{apgroup_name},
			port_number($aps->{$ethmac}{neighbor_port}),
			$ethmac
		);
		push(@json_array, \@ap);
	}

	my %json_data;
	$json_data{data} = \@json_array;
	my $json = encode_json \%json_data;
	
	print header();
	print $json;
	
} elsif($page =~ m/^apwlc$/){
	## AP WLC Priority (change/move APs between WLCs)
	my $aps = $aplol->get_active_aps();
	
	my @json_array;
	
	foreach my $ethmac (keys %$aps){
		next if($aps->{$ethmac}{model} =~ m/OEAP/); # don't want OEAPs

		my $neighbor_addr = $aps->{$ethmac}{neighbor_addr};
		$neighbor_addr = "" if $neighbor_addr =~ m/^0\.0\.0\.0$/;

		my $ap_name;
		if($aps->{$ethmac}{associated} && $aps->{$ethmac}{active}){
			# it's online and active
			# make HTML-link
			$ap_name = qq(<a href="/apwlc.pl?ethmac=$ethmac&action=select">$aps->{$ethmac}{name}</a>);
		} else {
			$ap_name = $aps->{$ethmac}{name};
		}
			
		my @ap = (
			$ap_name,
			$aps->{$ethmac}{ip},
			$aps->{$ethmac}{model},
			$aps->{$ethmac}{wlc_name},
			$aps->{$ethmac}{neighbor_name},
			$neighbor_addr,
			$aps->{$ethmac}{neighbor_port},
			$aps->{$ethmac}{location_name},
			port_number($aps->{$ethmac}{neighbor_port}),
			$ethmac
		);
		push(@json_array, \@ap);
	}

	my %json_data;
	$json_data{data} = \@json_array;
	my $json = encode_json \%json_data;
	
	print header();
	print $json;

} elsif($page =~ m/^apwlcfix$/){
	## Fix APs placed on "wrong" WLCs based on VD
	my $aps = $aplol->get_aps_vd();
	my $wlcs = $aplol->get_wlcs();
	
	my @json_array;
	
	foreach my $ethmac (keys %$aps){
		next if($aps->{$ethmac}{model} =~ m/OEAP/); # don't want OEAPs
		next if($aps->{$ethmac}{model} =~ m/1810W/); # don't want 1810Ws
		next if($aps->{$ethmac}{model} =~ m/AP801/); # don't want AP801s
		next if($aps->{$ethmac}{model} =~ m/AP802/); # don't want AP802s
		next unless($aps->{$ethmac}{associated}); # only want associated APs
		
		# Special case where buildings should be on Lab WLC
		next if($aps->{$ethmac}{location_name} =~ m/Utsikta/);
		
		# check if associated WLC is the one it should be
		# if it is, we skip it, as we only want to display the ones that doesn't match
		next if($aps->{$ethmac}{vd_logical_wlc} == $aps->{$ethmac}{wlc_id});

		my $neighbor_addr = $aps->{$ethmac}{neighbor_addr};
		$neighbor_addr = "" if $neighbor_addr =~ m/^0\.0\.0\.0$/;
		
		# correct WLC
		my $correct_wlc = $wlcs->{$aps->{$ethmac}{vd_logical_wlc}}{name};

		my $ap_name;
		if($aps->{$ethmac}{associated} && $aps->{$ethmac}{active}){
			# it's online and active
			# make HTML-link
			$ap_name = qq(<a href="/apwlcfix.pl?ethmac=$ethmac|$correct_wlc&action=select">$aps->{$ethmac}{name}</a>);
		} else {
			$ap_name = $aps->{$ethmac}{name};
		}
			
		my @ap = (
			$ap_name,
			$aps->{$ethmac}{model},
			$aps->{$ethmac}{wlc_name},
			$correct_wlc,
			$aps->{$ethmac}{neighbor_name},
			$neighbor_addr,
			$aps->{$ethmac}{neighbor_port},
			$aps->{$ethmac}{location_name},
			$ethmac
		);
		push(@json_array, \@ap);
	}

	my %json_data;
	$json_data{data} = \@json_array;
	my $json = encode_json \%json_data;
	
	print header();
	print $json;

} elsif($page =~ m/^model$/){
	## All APs of a specific model
	my $model = $cgi->param('m');

	if($model){
		my $model_like;
		if($model =~ m/^non-3702$/){
			# show all non-3702's
			$model_like = 'AND aps.model NOT LIKE \'%3702%\'';
			$model_like .= ' AND aps.model NOT LIKE \'%OEAP%\'';
			$model_like .= ' AND aps.model NOT LIKE \'%AGN%\'';
			$model_like .= ' AND aps.model NOT LIKE \'%1532%\'';
			$model_like .= ' AND aps.model NOT LIKE \'%1810%\'';
		} else {
			$model_like = 'AND aps.model LIKE \'%' . $model . '%\'';
		}
		my $aps = $aplol->get_specific_model($model_like);
	
		my @json_array;
	
		foreach my $ethmac (keys %$aps){
			my $neighbor_addr = $aps->{$ethmac}{neighbor_addr};
			$neighbor_addr = "" if $neighbor_addr =~ m/^0\.0\.0\.0$/;
		
			my @ap = (
				$aps->{$ethmac}{name},
				$aps->{$ethmac}{ip},
				$aps->{$ethmac}{model},
				$aps->{$ethmac}{wlc_name},
				$aps->{$ethmac}{neighbor_name},
				$neighbor_addr,
				$aps->{$ethmac}{neighbor_port},
				$aps->{$ethmac}{location_name},
				port_number($aps->{$ethmac}{neighbor_port})
			);
			push(@json_array, \@ap);
		}
	
		my %json_data;
		$json_data{data} = \@json_array;
		my $json = encode_json \%json_data;
		
		print header();
		print $json;
	} else {
		print CGI::header(
			-type => 'text/plain',
			-status => '404',
			-charset => 'utf-8'
		);
		$aplol->disconnect();
		exit 0;
	}
	
} elsif($page =~ m/^ip$/){
	## All APs from a specific subnet
	my $subnet = $cgi->param('subnet');

	if($subnet){
		my $aps = $aplol->get_specific_subnet($subnet);
	
		my @json_array;
	
		foreach my $ethmac (keys %$aps){
			my $neighbor_addr = $aps->{$ethmac}{neighbor_addr};
			$neighbor_addr = "" if $neighbor_addr =~ m/^0\.0\.0\.0$/;
		
			my @ap = (
				$aps->{$ethmac}{name},
				$aps->{$ethmac}{ip},
				$aps->{$ethmac}{model},
				$aps->{$ethmac}{wlc_name},
				nice_uptime($aps->{$ethmac}{uptime}),
				$aps->{$ethmac}{neighbor_name},
				$neighbor_addr,
				$aps->{$ethmac}{neighbor_port},
				port_number($aps->{$ethmac}{neighbor_port})
			);
			push(@json_array, \@ap);
		}
	
		my %json_data;
		$json_data{data} = \@json_array;
		my $json = encode_json \%json_data;
		
		print header();
		print $json;
	} else {
		print CGI::header(
			-type => 'text/plain',
			-status => '404',
			-charset => 'utf-8'
		);
		$aplol->disconnect();
		exit 0;
	}
	
} elsif($page =~ m/^apdiff$/){
	## APs that are not present in PI, or have mismatching information
	my $aps = $aplol->get_aps_diff();
	
	my @json_array;
	
	foreach my $ethmac (keys %$aps){
		my @ap = (
			$aps->{$ethmac}{name},
			$ethmac,
			$aps->{$ethmac}{model},
			$aps->{$ethmac}{wlc_name},
			$aps->{$ethmac}{db_wlc_name},
			$aps->{$ethmac}{apgroup_name},
			$aps->{$ethmac}{db_apgroup_name}
		);
		push(@json_array, \@ap);
	}
	
	my %json_data;
	$json_data{data} = \@json_array;
	my $json = encode_json \%json_data;
	
	print header();
	print $json;
	
	
} elsif($page =~ m/^missingcdp$/){
	## APs with missing CDP-info
	my $aps = $aplol->get_active_aps();

	my @json_array;

	foreach my $ethmac (keys %$aps){
		
		# Skip unwanted APs
		if (
			# We only want associated APs
			( $aps->{$ethmac}{associated} == 0 ) ||
			
			# We don't want OEAPs
			( $aps->{$ethmac}{model} =~ m/OEAP/ ) ||
			
			# We don't want APs on DMZ WLC
			( $aps->{$ethmac}{wlc_name} =~ m/dmz/ ) ||
						
			# We only want those without CDP-neighbor
			( $aps->{$ethmac}{no_cdp} == 0 )		
		){
			next;
		}
		
		my @ap = (
			$aps->{$ethmac}{name},
			$aps->{$ethmac}{ip},
			$aps->{$ethmac}{model},
			$aps->{$ethmac}{wlc_name},
			nice_uptime($aps->{$ethmac}{uptime})
		);
		push(@json_array, \@ap);
	}

	my %json_data;
	$json_data{data} = \@json_array;
	my $json = encode_json \%json_data;

	print header();
	print $json;

} elsif($page =~ m/^apswithperiod$/){
	## APs containing periods
	my $aps = $aplol->get_active_aps();
	
	my @json_array;
	
	foreach my $ethmac (keys %$aps){
		
		# Skip unwanted APs
		unless (
			# We only want APs with period in the name
			( $aps->{$ethmac}{name} =~ m/\./ ) &&
			
			# We don't want OEAPs
			( $aps->{$ethmac}{model} !~ m/OEAP/ )						
		){
			next;
		}
		
		my $neighbor_addr = $aps->{$ethmac}{neighbor_addr};
		$neighbor_addr = "" if $neighbor_addr =~ m/^0\.0\.0\.0$/;
		
		my @ap = (
			$aps->{$ethmac}{name},
			$aps->{$ethmac}{ip},
			$aps->{$ethmac}{model},
			$aps->{$ethmac}{wlc_name},
			nice_uptime($aps->{$ethmac}{uptime}),
			$aps->{$ethmac}{neighbor_name},
			$neighbor_addr,
			$aps->{$ethmac}{neighbor_port},
			port_number($aps->{$ethmac}{neighbor_port})
		);
		push(@json_array, \@ap);
	}
	
	my %json_data;
	$json_data{data} = \@json_array;
	my $json = encode_json \%json_data;
	
	print header();
	print $json;
	

} elsif($page =~ m/^graph-total$/){
	## Total number of APs
	my $callback = $cgi->param('callback');
	my $start = $cgi->param('start');
	my $end = $cgi->param('end');
	my (@db_array, @json_array);
		
	if($start && $end){
		$start = int($start / 1000);
		$end = int($end / 1000);
	} else {
		# all data
		$end = time();
		$start = 0; # the beginning
	}
	
	# get all counts
	my $total_count = $aplol->get_graph_total($start, $end);

	# organize data
	foreach my $id (sort { $total_count->{$a}{date} cmp $total_count->{$b}{date} } keys %$total_count){
		push(@db_array, [int($total_count->{$id}{date}*1000), int($total_count->{$id}{count})]);
	}
	
	# put into correct structure
	my %total_hash;
	$total_hash{name} = "Total";
	$total_hash{data} = \@db_array;
	push(@json_array, \%total_hash);
	
	# make json
	my $json = encode_json \@json_array;
	
	if($callback){
		$json = $callback . "(" . $json  . ");";
	}
	
	print header();
	print $json;

} elsif($page =~ m/^graph-vd$/){
	## Number of APs per Virtual Domain
	my $callback = $cgi->param('callback');
	my $start = $cgi->param('start');
	my $end = $cgi->param('end');
	my (%db_hash, @json_array);
		
	if($start && $end){
		$start = int($start / 1000);
		$end = int($end / 1000);
	} else {
		# all data
		$end = time();
		$start = 0; # the beginning
	}
	
	# get all VDs
	my $vd_count = $aplol->get_graph_vd_all($start, $end);

	# organize data
	foreach my $entry (@$vd_count){
		push(@{$db_hash{$entry->{description}}}, [int($entry->{date}*1000), int($entry->{count})]);
	}
	
	# put into correct structure
	foreach my $vd (sort {$a cmp $b} keys %db_hash){
		my %json_hash;
		$json_hash{name} = "$vd";
		$json_hash{data} = \@{$db_hash{$vd}};
		push(@json_array, \%json_hash);
	}
	
	# make json
	my $json = encode_json \@json_array;
	
	if($callback){
		$json = $callback . "(" . $json  . ");";
	}
	
	print header();
	print $json;

} elsif($page =~ m/^graph-wlc$/){
	## Number of APs per WLC
	my $callback = $cgi->param('callback');
	my $start = $cgi->param('start');
	my $end = $cgi->param('end');
	my (%db_hash, @json_array);
	
	if($start && $end){
		$start = int($start / 1000);
		$end = int($end / 1000);
	} else {
		# all data
		$end = time();
		$start = 0; # the beginning
	}
	
	# get all WLCs
	my $wlc_count = $aplol->get_graph_wlc_all($start, $end);

	# organize data
	foreach my $entry (@$wlc_count){
		push(@{$db_hash{$entry->{name}}}, [int($entry->{date}*1000), int($entry->{count})]);
	}
	
	# put into correct structure
	foreach my $wlc (sort {$a cmp $b} keys %db_hash){
		my %json_hash;
		$json_hash{name} = "$wlc";
		$json_hash{data} = \@{$db_hash{$wlc}};
		push(@json_array, \%json_hash);
	}
	
	# make json
	my $json = encode_json \@json_array;
	
	if($callback){
		$json = $callback . "(" . $json  . ");";
	}
	
	print header();
	print $json;
	
} elsif($page =~ m/^graph-clients$/){
	## Number of APs per WLC
	my $callback = $cgi->param('callback');
	my $start = $cgi->param('start');
	my $end = $cgi->param('end');
	my (%db_hash, @json_array);
	
	if($start && $end){
		$start = int($start / 1000);
		$end = int($end / 1000);
	} else {
		# all data
		$end = time();
		$start = 0; # the beginning
	}
	
	# get all WLCs
	my $client_count = $aplol->get_graph_clients_all($start, $end);

	# organize data
	foreach my $entry (@$client_count){
		push(@{$db_hash{$entry->{type}}}, [int($entry->{date}*1000), int($entry->{count})]);
	}
	
	# put into correct structure
	foreach my $type (sort {$a cmp $b} keys %db_hash){
		my %json_hash;
		$json_hash{data} = \@{$db_hash{$type}};
		
		# Fix names
		$type =~ s/total/Total/;
		$type =~ s/2ghz/2.4GHz/;
		$type =~ s/5ghz/5GHz/;
		
		$json_hash{name} = "$type";
		push(@json_array, \%json_hash);
	}
	
	# make json
	my $json = encode_json \@json_array;
	
	if($callback){
		$json = $callback . "(" . $json  . ");";
	}
	
	print header();
	print $json;

} else {
	## Not a valid table
	print CGI::header(
		-type => 'text/plain',
		-status => '404',
		-charset => 'utf-8'
	);
	$aplol->disconnect();
	exit 0;
}

# done
$aplol->disconnect();
exit 0;
