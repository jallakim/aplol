#!/usr/bin/perl
# From command-line;
#     https_proxy= HTTPS_PROXY= perl aplol-ciscopi-aps.pl
use warnings;
use strict;
use POSIX qw(strftime);
use POSIX qw(floor);
use Fcntl qw(:flock);
use Date::Parse;
use Scalar::Util qw/reftype/;
binmode(STDOUT, ":utf8");

# Counts number of APs with/without CDP-information

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
my (%locations, $root_aps, $time_start);

# Log
sub log_it{
	$aplol->log_it("ciscopi-apinfo", "@_");
}

# Logs debug-stuff if debug has been turned on
sub debug_log{
	$aplol->debug_log("ciscopi-apinfo", "@_");
}

# Logs error-stuff
sub error_log{
	$aplol->error_log("ciscopi-apinfo", "@_");
}

# Shows runtime
sub show_runtime{
	my $runtime = time() - $time_start;
	log_it("Took $runtime seconds to complete.");
}

# fetch AP info
sub get_apinfo{
	my $vd = shift;
	my $url = "data/AccessPointDetails.json?.full=true&type=\"UnifiedAp\"&_ctx.domain=$vd&.maxResults=1000";
	return $aplol->get_json($url);
}

# fetch all APs
sub get_aps{
	my $vd = "ROOT-DOMAIN";
	my $pi_aps = get_apinfo($vd);
	my ($total, $total_with, $total_without) = (0, 0, 0);
	
	if($pi_aps){
		foreach my $apinfo (@$pi_aps){
			
			# next if DMZ-WLC
			if( $apinfo->{'accessPointDetailsDTO'}->{'unifiedApInfo'}->{'controllerName'} ){
				if( $apinfo->{'accessPointDetailsDTO'}->{'unifiedApInfo'}->{'controllerName'} =~ m/dmz/ ){
					next;
				}
			}
			
			# next if OEAP
			if( $apinfo->{'accessPointDetailsDTO'}->{'model'} =~ m/OEAP/ ){
				next;
			}
			
			# neighbor count
			my $neighbor_count = keys %{$apinfo->{'accessPointDetailsDTO'}->{'cdpNeighbors'}->{'cdpNeighbor'}};

			if($neighbor_count == 0){
				$total_without++;
			} else {
				$total_with++;
			}

			$total++;
		}
	}
	
	print "Total APs: $total\n";
	print "Total APs with CDP: $total_with\n";
	print "Total APs without CDP: $total_without\n";
}


# We only want 1 instance of this script running
# Check if already running -- if so, abort.
unless (flock(DATA, LOCK_EX|LOCK_NB)) {
	die("$0 is already running. Exiting.");
}

# connect
$time_start = time(); # set start time
$aplol->connect();

get_aps();

# disconnect
$aplol->disconnect();

# how long did it take?
show_runtime();


__DATA__
Do not remove. Makes sure flock() code above works as it should.
