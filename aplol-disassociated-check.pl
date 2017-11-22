#!/usr/bin/perl
# From command-line;
#     https_proxy= HTTPS_PROXY= perl aplol-test.pl
use warnings;
use strict;
use POSIX qw(strftime);
use POSIX qw(floor);
use Fcntl qw(:flock);
use Date::Parse;
use Scalar::Util qw/reftype/;
binmode(STDOUT, ":utf8");

# Alarm-check for Cisco Prime
# Checks wether or not alarms are cleared if APs are online

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
	$aplol->log_it("disassociated-check", "@_");
}

# Logs debug-stuff if debug has been turned on
sub debug_log{
	$aplol->debug_log("disassociated-check", "@_");
}

# Logs error-stuff
sub error_log{
	$aplol->error_log("disassociated-check", "@_");
}

# Shows runtime
sub show_runtime{
	my $runtime = time() - $time_start;
	log_it("Took $runtime seconds to complete.");
}

# We only want 1 instance of this script running
# Check if already running -- if so, abort.
unless (flock(DATA, LOCK_EX|LOCK_NB)) {
	die("$0 is already running. Exiting.");
}

# connect
$time_start = time(); # set start time
$aplol->connect();

my %alarms;

while (my $line=<STDIN>){
	next unless ($line =~ m/AP '(.+)' disassociated/);
	my $apname = $1;
	
	my $apinfo = $aplol->get_apinfo_name($apname);
	$alarms{$apname} = 1;
	
	if($apinfo){
		# we have info
		if($apinfo->{associated}){
			# ap is associated according to the API
			print "We have disassociated alarm for '$apinfo->{name}', but the AP is online on WLC '$apinfo->{wlc_name}'.\n"
			#use Data::Dumper;
			#print Dumper($apinfo);
		}
	} else {
		error_log("Could not get apinfo for AP $apname");
	}
}

my $aps = $aplol->get_aps();

foreach my $apethmac (sort keys %$aps){
	# we only want active + disassociated
	next unless ($aps->{$apethmac}{active} && !$aps->{$apethmac}{associated});
	
	
	
	if ($alarms{$aps->{$apethmac}{name}}){
		# we have alarm for this
		next;
	} else {
		# we have an AP down with no alarm
		print("We have an AP ($aps->{$apethmac}{name}) that is offline according to the API, but with no alarm.\n");
	}
}

# disconnect
$aplol->disconnect();

# how long did it take?
show_runtime();


__DATA__
Do not remove. Makes sure flock() code above works as it should.
