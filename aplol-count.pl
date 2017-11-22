#!/usr/bin/perl
use warnings;
use strict;
use Fcntl qw(:flock);

# Count number of APs

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
	$aplol->log_it("count", "@_");
}

# Logs debug-stuff if debug has been turned on
sub debug_log{
	$aplol->debug_log("count", "@_");
}

# Logs error-stuff
sub error_log{
	$aplol->error_log("count", "@_");
}

# Update VD-count
sub update_vd_count{	
	my $vd_count = $aplol->get_vd_count();
	
	foreach my $vd_id (keys %$vd_count){
		$aplol->add_count($vd_id, $vd_count->{$vd_id}{count}, 'vd');
	}
}

# Update WLC-count
sub update_wlc_count{
	my $wlc_count = $aplol->get_wlc_count();
	
	foreach my $wlc_id (keys %$wlc_count){
		$aplol->add_count($wlc_id, $wlc_count->{$wlc_id}{count}, 'wlc');
	}	
}

# Update total count
sub update_total_count{
	my $total_count = $aplol->get_total_count();
	
	$aplol->add_total_count($total_count);
}

# We only want 1 instance of this script running
# Check if already running -- if so, abort.
unless (flock(DATA, LOCK_EX|LOCK_NB)) {
	die("$0 is already running. Exiting.");
}

$aplol->connect();
	
# Update VD-count
update_vd_count();

# Update WLC-count
update_wlc_count();

# Update total count
update_total_count();
	
$aplol->disconnect();


__DATA__
Do not remove. Makes sure flock() code above works as it should.
