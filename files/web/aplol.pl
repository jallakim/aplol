#!/usr/bin/perl
use warnings;
use strict;
use CGI;
use JSON;
use Time::Local;
use POSIX qw(strftime);
use POSIX qw(floor);

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
	## Unassigned AP's
	my $aps = $aplol->get_unassigned_aps();
	
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
	
} elsif($page =~ m/^unassociated$/){
	## Unassociated AP's
	my $aps = $aplol->get_unassociated_aps();
	
	my @json_array;
	
	foreach my $ethmac (keys %$aps){
		my $neighbor_addr = $aps->{$ethmac}{neighbor_addr};
		$neighbor_addr = "" if $neighbor_addr =~ m/^0\.0\.0\.0$/;
		
		my @ap = (
			$aps->{$ethmac}{name},
			$aps->{$ethmac}{ip},
			$aps->{$ethmac}{model},
			$aps->{$ethmac}{neighbor_name},
			$neighbor_addr,
			$aps->{$ethmac}{neighbor_port},
			$aps->{$ethmac}{location_name},
			$aps->{$ethmac}{alarm},
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
	## AP's member of only ROOT-DOMAIN
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
	## All active AP's regardless of status
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

} elsif($page =~ m/^apgroup$/){
	## AP groups
	my $aps = $aplol->get_active_aps();
	
	my @json_array;
	
	foreach my $ethmac (keys %$aps){
		next if($aps->{$ethmac}{model} =~ m/OEAP/); # don't want OEAP's

		my $neighbor_addr = $aps->{$ethmac}{neighbor_addr};
		$neighbor_addr = "" if $neighbor_addr =~ m/^0\.0\.0\.0$/;

		my $ap_name;
		if($aps->{$ethmac}{associated}){
			# it's online, and we should have OID-info
			# make HTML-link
			$ap_name = qq(<a href="/apgroup.pl?ethmac=$ethmac&action=select">$aps->{$ethmac}{name}</a>);
		} else {
			$ap_name = $aps->{$ethmac}{name};
		}
		
		my @ap = (
			$ap_name,
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

} elsif($page =~ m/^model$/){
	## All AP's of a specific model
	my $model = $cgi->param('m');

	if($model){
		my $aps = $aplol->get_specific_model($model);
	
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
	
} elsif($page =~ m/^apdiff$/){
	## AP's that are not present in PI, or have mismatching information
	my $aps = $aplol->get_aps_diff();
	
	my @json_array;
	
	foreach my $ethmac (keys %$aps){
		my @ap = (
			$aps->{$ethmac}{name},
			$ethmac,
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
	
} elsif($page =~ m/^graph-total$/){
	## Total number of AP's
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
		$start = $end - (365 * 24 * 60 * 60 * 100); # 100 years ago
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
	## Number of AP's per Virtual Domain
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
		$start = $end - (365 * 24 * 60 * 60 * 100); # 100 years ago
	}
	
	# get all VDs
	my $vd_count = $aplol->get_graph_vd_all($start, $end);

	# organize data
	foreach my $entry (@$vd_count){
		push(@{$db_hash{$entry->{description}}}, [int($entry->{date}*1000), int($entry->{count})]);
	}
	
	# put into correct structure
	foreach my $vd (sort {$a cmp $b} keys %db_hash){
		my %vd_hash;
		$vd_hash{name} = "$vd";
		$vd_hash{data} = \@{$db_hash{$vd}};
		push(@json_array, \%vd_hash);
	}
	
	# make json
	my $json = encode_json \@json_array;
	
	if($callback){
		$json = $callback . "(" . $json  . ");";
	}
	
	print header();
	print $json;

} elsif($page =~ m/^graph-wlc$/){
	## Number of AP's per WLC
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
		$start = $end - (365 * 24 * 60 * 60 * 100); # 100 years ago
	}
	
	# get all WLCs
	my $wlc_count = $aplol->get_graph_wlc_all($start, $end);

	# organize data
	foreach my $entry (@$wlc_count){
		push(@{$db_hash{$entry->{name}}}, [int($entry->{date}*1000), int($entry->{count})]);
	}
	
	# put into correct structure
	foreach my $wlc (sort {$a cmp $b} keys %db_hash){
		my %wlc_hash;
		$wlc_hash{name} = "$wlc";
		$wlc_hash{data} = \@{$db_hash{$wlc}};
		push(@json_array, \%wlc_hash);
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
