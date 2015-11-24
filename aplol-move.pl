#!/usr/bin/perl
use warnings;
use strict;
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
	$aplol->log_it("move", "@_");
}

# Logs debug-stuff if debug has been turned on
sub debug_log{
	$aplol->debug_log("move", "@_");
}

# Logs error-stuff
sub error_log{
	$aplol->error_log("move", "@_");
}

# We only want 1 instance of this script running
# Check if already running -- if so, abort.
unless (flock(DATA, LOCK_EX|LOCK_NB)) {
	die("$0 is already running. Exiting.");
}

# move file to archive
log_it("Moving files from '$config{path}->{new_reports}' to '$config{path}->{old_reports}'...");
(system("/bin/mv -f $config{path}->{new_reports}/*.csv $config{path}->{old_reports}/") == 0) or die("Moving files from '$config{path}->{new_reports}' to '$config{path}->{old_reports}' failed.");

__DATA__
Do not remove. Makes sure flock() code above works as it should.
