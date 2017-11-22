#!/usr/bin/perl
use warnings;
use strict;
use Net::LDAP;
use Net::LDAP::Control::Paged;
use Net::LDAP::Constant qw( LDAP_CONTROL_PAGED );
use Net::LDAP::Util qw(ldap_error_text);
use Fcntl qw(:flock);

# Updates LDAP-database with MAC-address from our database

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

# variabler
my ($ldap, $pi_info);
my %ldap_info;
my ($added, $deleted) = (0, 0);

# Log
sub log_it{
	$aplol->log_it("adlds", "@_");
}

# Logs debug-stuff if debug has been turned on
sub debug_log{
	$aplol->debug_log("adlds", "@_");
}

# Logs error-stuff
sub error_log{
	$aplol->error_log("adlds", "@_");
}

# Wrapper for a Net::LDAP call- assert the server message is a "success"
# code- die with a decoded error message if it isn't
sub ldapassert{
	my $mesg = shift;
	my $op = shift;
	$mesg->code && die error_log("LDAP error" . ($op?" during $op":"") . ": " . ldap_error_text($mesg->code));
	$mesg;
}

# Fetch stuff from LDAP into hash
sub fetch_from_ldap{
	# Default LDAP allows 1000 entries per "page" requested
	# We have to do pagination of results -- request 999 each time
	my $page = Net::LDAP::Control::Paged->new(size => 999);
	my $cookie;

	my @search_args = (
		base    => $config{adlds}->{path},
	        scope   => "sub",
	        filter  => "(&)",
	        control => [$page],
	);

	while (1) {
		my $ldap_search = ldapassert($ldap->search(@search_args), "MAC search");

		if ($ldap_search->count < 1){
			die error_log("No results.");
		}

		foreach my $ldap_entry ($ldap_search->entries){
			# Fetch name of entry (so that we can skip entry equal to $config{adlds}->{path}).
			my $dn = $ldap_entry->get_value('distinguishedName');
			next if ($dn =~ m/^${config{adlds}->{path}}$/);
	
			# Fetch other stuff
			my $mac = $ldap_entry->get_value('displayName');
			my $apname = $ldap_entry->get_value('adminDisplayName');

			# Skip if no values
			next unless ($mac && $apname);

			# TODO: Check values for $mac-entry against MAC-regex

			# Replace MAC so that we get same as from Cisco PI
			$mac =~ s/\-/\:/g;

			my %host = (
	                        mac => $mac,
	                        apname => $apname,
	                );      
        
	                $ldap_info{$mac} = \%host;
		}

		# Do pagination-stuff
		my $resp = $ldap_search->control(LDAP_CONTROL_PAGED) or last;
		$cookie = $resp->cookie or last;
		# Paging Control
		$page->cookie($cookie);
	}

	if ($cookie){
		error_log("Abnormal exit from LDAP-search.");
		# Abnormal exit, so let the server know we do not want any more
		$page->cookie($cookie);
		$page->size(0);
		$ldap->search(@search_args);
		exit(-1);
	}
}

# Sync entries
sub sync_entries{
	# After fetching everything from PI and LDAP, we want to sync them
	# PI-database should be authorative -- that is, if an item is deleted
	# from PI, it should be deleted on LDAP, and if an item is added to
	# PI, it should be added on LDAP. However, units deleted/added to LDAP
	# should not reflect back to the PI-server.
	
	# Since PI is authorative, we iterate through all entries found in PI.
	# We then check if it's present on both PI and LDAP. We delete entries
	# from the hashes that is present both places. Once iterated through all
	# PI-entries, we can go ahead to add/delete from LDAP.
	#   1) All entries still in the PI-hash should be added to LDAP.
	#   2) All entries still in the LDAP-hash should be deleted from LDAP.

	foreach my $ethmac (keys %$pi_info){
		if ($ldap_info{$ethmac}){
			# Entry exists both in LDAP and PI
			# Delete from both places
			delete($pi_info->{$ethmac});
                        delete($ldap_info{$ethmac});

			## TODO: Update VD/location in LDAP here
		}
	}

	# At this point we should add/delete to LDAP-database
	# First, we delete
	foreach my $mac (keys %ldap_info){
		# delete from LDAP
		delete_ldap_entry($mac, \%ldap_info);
	}

	# Then we add from PI
	foreach my $ethmac (keys %$pi_info){
		# add to LDAP
		add_ldap_entry($ethmac, $pi_info);
	}
}

# Delete entry from LDAP
sub delete_ldap_entry{
	my ($mac, $hash) = @_;

	debug_log("Deleting entry $mac ($hash->{$mac}{apname})...");

	(my $prettymac = $mac) =~ s/\:/\-/g;
        my $ldap_mac = "MAC_" . $prettymac;

        my $entry_dn = "CN=$ldap_mac," . $config{adlds}->{path};

	ldapassert($ldap->delete($entry_dn), "entry deletion");
	$deleted++;
}

# Add entry to LDAP
sub add_ldap_entry{
	my ($ethmac, $hash) = @_;
	my $ap_name = $hash->{$ethmac}{name};		

	debug_log("Adding entry $ethmac ($ap_name)...");
	
	(my $prettymac = $ethmac) =~ s/\:/\-/g;
	my $ldap_mac = "MAC_" . $prettymac;
	
	my $mac_dn = "CN=$ldap_mac," . $config{adlds}->{path};

	my @attributes = (
		objectClass => [ "top", "person", "organizationalPerson", "user" ],
		cn => "$ldap_mac",
		name => "$ldap_mac",
		displayName => "$prettymac",	
		adminDisplayName => "$ap_name",
		houseIdentifier => $config{adlds}->{create_message},
	);

	ldapassert($ldap->add($mac_dn, attrs => \@attributes), "MAC adding");
	$added++;

	# Add to group
	# First, fetch group-entry
	my @search_args = (
                base    => $config{adlds}->{group_dn},
                scope   => "sub",
                filter  => "(&)",
        );

	my $sr = ldapassert($ldap->search(@search_args), "group search");
	if ($sr->count == 0) {
		die error_log("Unknown group.");
	} elsif ($sr->count > 1) {
		die error_log("Ambiguous group.");
	}

	my $group_entry = $sr->shift_entry;

	# Update the group entry
	$group_entry->add(member => $mac_dn);

	# Update LDAP
	ldapassert($group_entry->update($ldap), "group update");
}

# We only want 1 instance of this script running
# Check if already running -- if so, abort.
unless (flock(DATA, LOCK_EX|LOCK_NB)) {
	die("$0 is already running. Exiting.");
}

# connect
$aplol->connect();
$ldap = Net::LDAP->new($config{adlds}->{hostname} . ":" . $config{adlds}->{port}) or die error_log("LDAP server could not be contacted. Error: $@");

# Bind to LDAP
ldapassert($ldap->bind($config{adlds}->{username}, password=> $config{adlds}->{password}), "bind");

# Fetch AP's from PI
$pi_info = $aplol->get_active_aps();

# do our magic
fetch_from_ldap();
sync_entries();

# print stats
log_it("$added entries added.");
log_it("$deleted entries deleted.");

# disconnect
my $disconnect = $ldap->unbind;
$aplol->disconnect();



__DATA__
Do not remove. Makes sure flock() code above works as it should.
