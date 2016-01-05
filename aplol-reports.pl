#!/usr/bin/perl
use warnings;
use strict;
use FindBin;
use File::Find;
use Fcntl qw(:flock);
use Encode;

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

# variables
my $working_depth = ($config{path}->{new_reports} =~ tr,/,,) + 1;
my $file_count = 0;
my %virtual_domains; # ap per VD
my %aps; # ap by name
my %locations; # VD for each location

# Log
sub log_it{
	$aplol->log_it("reports", "@_");
}

# Logs debug-stuff if debug has been turned on
sub debug_log{
	$aplol->debug_log("reports", "@_");
}

# Logs error-stuff
sub error_log{
	$aplol->error_log("reports", "@_");
}

# check if array contains entry
sub array_contains{
	my ($array, $value) = @_;
	
	foreach my $element (@$array){
		return 1 if($element =~ m/$value/);
	}
	
	return 0;
}

# add ap to hash
sub add_ap{
	my ( $vd, $ap_info, $associated ) = @_;	
	chomp($ap_info);
	
	# do some replace (due to PI failing to do ÆØÅ)
	# added at the very beginning	
	$ap_info =~ s/\?yane/Øyane/g;
	$ap_info =~ s/\?rdal/Årdal/g;
	$ap_info =~ s/\?sane/Åsane/g;
	$ap_info =~ s/Ask\?y/Askøy/g;
	$ap_info =~ s/B\?mlo/Bømlo/g;
	$ap_info =~ s/Bj\?rndalen/Bjørndalen/g;
	$ap_info =~ s/Nyg\?rdsgaten/Nygårdsgaten/g;
	$ap_info =~ s/Bl\?/Blå/g;
	$ap_info =~ s/Murhj\?rnet/Murhjørnet/g;
	$ap_info =~ s/F\?rde/Førde/g;
	$ap_info =~ s/Direkt\?r/Direktør/g;
	$ap_info =~ s/Flor\?/Florø/g;
	$ap_info =~ s/Bj\?dnabeen/Bjødnabeen/g;
	$ap_info =~ s/g\?rden/gården/g;
	$ap_info =~ s/H\?yanger/Høyanger/g;
	$ap_info =~ s/Vognst\?len/Vognstølen/g;
	$ap_info =~ s/\?ye/Øye/g;
	$ap_info =~ s/Hillev\?g/Hillevåg/g;
	$ap_info =~ s/J\?ren/Jæren/g;
	$ap_info =~ s/Karm\?y/Karmøy/g;
	$ap_info =~ s/Lind\?s/Lindås/g;
	$ap_info =~ s/M\?l\?y/Måløy/g;
	$ap_info =~ s/V\?gs\?y/Vågsøy/g;
	$ap_info =~ s/hj\?rnet/hjørnet/g;
	$ap_info =~ s/Nord\?s/Nordås/g;
	$ap_info =~ s/Oster\?y/Osterøy/g;
	$ap_info =~ s/Rad\?y/Radøy/g;
	$ap_info =~ s/Bj\?rgvin/Bjørgvin/g;
	$ap_info =~ s/\?stbygg/Østbygg/g;
	$ap_info =~ s/J\?lster/Jølster/g;
	$ap_info =~ s/\?stre/Østre/g;
	
	# added 2015-02-03
	$ap_info =~ s/J\?rpeland/Jørpeland/g;
	$ap_info =~ s/Presteb\?en/Prestebøen/g;
	$ap_info =~ s/M\?llendal/Møllendal/g;
	$ap_info =~ s/Utl\?ns/Utlåns/g;
	$ap_info =~ s/S\?sterheimen/Søsterheimen/g;
	$ap_info =~ s/p\?bygg/påbygg/g;
	$ap_info =~ s/Milj\?/Miljø/g;
	
	# spot the rest
	$ap_info =~ s/\?/LOL/g; # can easily find it if we missed something
	
	# UTF8-fucker
	$ap_info = Encode::decode('UTF-8', $ap_info);
	
	my ( 	$ap_name, $ap_ethmac, $ap_wmac, $ap_ip,
		$ap_model, $ap_location, $ap_controller, $neighbor_name, 
		$neighbor_addr, $neighbor_port ) = split(',', $ap_info);

	# remove whitespace from IP
	$neighbor_addr =~ s/\s//g;

	# remove domain from hostname
	$neighbor_name =~ s/^(.+?)\..*/$1/;

	# short portname
	$neighbor_port =~ s/GigabitEthernet/Gi/;
	$neighbor_port =~ s/FastEthernet/Fa/;
	
	# Sometimes there is no neighbor information
	unless($neighbor_addr){
		$neighbor_addr = "0.0.0.0";
	}

	my %ap = (
		name => $ap_name,
		ethmac => $ap_ethmac,
		wmac => $ap_wmac,
		ip => $ap_ip,
		model => $ap_model,
		location => $ap_location,
		controller => $ap_controller,
		associated => $associated,
		neighbor_name => $neighbor_name,
		neighbor_addr => $neighbor_addr,
		neighbor_port => $neighbor_port,
	);

	# add info to hashes
	$virtual_domains{$vd} = 1;
	$aps{$ap_ethmac} = \%ap unless $aps{$ap_ethmac}; # only add info once
	
	# add VD for this location
	unless ($locations{$ap_location}){
		$locations{$ap_location} = [];
	}
	unless (array_contains($locations{$ap_location}, $vd)){
		push(@{$locations{$ap_location}}, $vd);
	}
}

# find all files
sub find_new_reports{	
	find(\&process_reports, $config{path}->{new_reports});
}

# process files
sub process_reports{
	my $full_path = "$File::Find::name";
	my $file = "$_";
	
	# increment count
	$file_count++;
	
	# skip if it's the working dir (so that we don't delete it)
	return if ($full_path =~ m/^$config{path}->{working_folder}$/);
	
	# skip if subfolder
	# since we do recursive removal of invalid files,
	# we're only interested in the folder itself
	my $depth = ($full_path =~ tr,/,,);
	return if ($depth > $working_depth);
	
	# skip unless matching regex
	return unless ($file =~ m/^$config{regex}->{file}$/);
	
	# by now the file should be a file we want to process
	(my $vd = $file) =~ s/^$config{regex}->{vd}$/$1/;
	my $associated = 1;

	open(VD_FILE, '<', $full_path) or die("Can't open '$full_path': $!");
	while (<VD_FILE>) {
		next if m/^\s*$/; # only whitespace, skip
		
		# new in PI2.2
		next if m/^AP-count_/; # first line, contains the report name (without datestamp/etc)
		next if m/^Generated\:/; # second line, shows when the report was generated
		next if m/^None\./; # if there are no disassociated AP's
		
		# prior to PI2.2, still present in PI2.2
		next if m/^AP Inventory/; # what type of report it is
		next if m/^AP Name,/; # line containing descriptions for all the CSV-fields
		
		# prior to PI2.2, not present in PI2.2
		next if m/^No data found/; # if there are no disassociated AP's
	
		if (m/^Disassociated/){
			$associated = 0;
			next;
		}
		add_ap($vd, $_, $associated);
	}
	close(VD_FILE) or die("Can't close '$full_path': $!");
}

# update all VD's
sub update_vds{
	# get all VD's from DB
	my $db_vds = $aplol->get_vds();
	
	# delete all entries present in both lists
	foreach my $vd (keys %virtual_domains){
		if($db_vds->{$vd}){
			# delete from both
			delete($virtual_domains{$vd});
                        delete($db_vds->{$vd});
		}
	}

	# then delete everything from DB that 
	# only has an entry in the DB
	if ($config{switch}->{delete_vd}){
		foreach my $vd (keys %$db_vds){
			# delete from DB
			$aplol->delete_vd($vd);
		}
	}

	# then add everything to DB that has
	# an entry in the report list
	foreach my $vd (keys %virtual_domains){
		$aplol->add_vd($vd, $vd); # name, desc
	}
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
	
	foreach my $ethmac (sort keys %aps){
		if($db_aps->{$ethmac}){
			# update AP-info
			update_ap($wlcs, $ethmac);
						
			# delete from both
			delete($aps{$ethmac});
                        delete($db_aps->{$ethmac});
		}
	}
		
	# deactivate if only present in DB
	foreach my $ethmac (keys %$db_aps){
		$aplol->deactivate_ap($ethmac);
	}
	
	# add to DB if not present
	foreach my $ethmac (keys %aps){
		my $wlc_id = get_wlc_id($wlcs, $ethmac);
		unless(defined($wlc_id)){
			error_log("Controller '$aps{$ethmac}{controller}' does not exist in DB. Please fix.");
			next;
		}
		
		my $location_id = get_location_id($ethmac);
		unless(defined($location_id)){
			error_log("Location '$aps{$ethmac}{location}' does not exist in DB. Please fix.");
			next;
		}
				
		# at this point we should have valid $wlc_id and $location_id
		$aps{$ethmac}{wlc_id} = $wlc_id;
		$aps{$ethmac}{location_id} = $location_id;
		
		$aplol->add_ap($aps{$ethmac});
	}
}

# find WLC ID, if associated
sub get_wlc_id{
	my ($wlcs, $ethmac) = @_;
	
	my $wlc_id;
	if ($aps{$ethmac}{controller} =~ m/^Not Associated$/){
		# not associated
		$wlc_id = '0';
	} else {
		# associated	
		if ($wlcs->{$aps{$ethmac}{controller}}){
			# controller exists in DB
			$wlc_id = $wlcs->{$aps{$ethmac}{controller}}{id};
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
	my $location_item = $aplol->get_location($aps{$ethmac}{location});
	
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
		error_log("Controller '$aps{$ethmac}{controller}' does not exist in DB. Please fix.");
		return;
	}
	
	my $location_id = get_location_id($ethmac);
	unless(defined($location_id)){
		error_log("Location '$aps{$ethmac}{location}' does not exist in DB. Please fix.");
		return;
	}
				
	# at this point we should have valid $wlc_id and $location_id
	$aps{$ethmac}{wlc_id} = $wlc_id;
	$aps{$ethmac}{location_id} = $location_id;
	
	$aplol->update_ap($aps{$ethmac});
}

# We only want 1 instance of this script running
# Check if already running -- if so, abort.
unless (flock(DATA, LOCK_EX|LOCK_NB)) {
	die("$0 is already running. Exiting.");
}

# process reports
find_new_reports();

if($file_count > 2){
	# all OK, update DB
	$aplol->connect();
	
	# add all VD's
	update_vds();
	
	# update all locations
	update_locations();
	
	# update all AP's
	update_aps();
	
	$aplol->disconnect();
} else {
	error_log("No reports found.");
	exit 1;
}

__DATA__
Do not remove. Makes sure flock() code above works as it should.

