#!/usr/bin/env perl
use strict;
use warnings;
use DBI;
use Config::General;
use POSIX qw(strftime);

# Define aplol-dir, and add it to %INC
my $aplol_dir;
BEGIN {
	use FindBin;
	$aplol_dir = "$FindBin::Bin"; # Assume working-folder is the path where this script resides
	if($aplol_dir =~ m/files\/web/){
		$aplol_dir .= "/../.."; # two levels up if via web
	}
}
use lib $aplol_dir;

package aplol;

# Load config
my $config_file = "$aplol_dir/aplol.conf";
my $conf = Config::General->new(
	-ConfigFile => $config_file,
	-InterPolateVars => 1);
my %config = $conf->getall;

# Variables
my $silent_logging = 0;
my $LOG_FILE;

my $sql_statements = {
	get_vds =>		"	SELECT 	*
	
					FROM	virtual_domains
				",
	delete_vd =>		"	DELETE 	FROM virtual_domains

					WHERE 	(name = ?)
				",	
	add_vd =>		"	INSERT	INTO virtual_domains
						(name, description)
						
					VALUES	(?, ?)
				",	
	get_locations =>	"	SELECT 	*

					FROM	locations
				",
	delete_location =>	"	DELETE 	FROM locations

					WHERE 	(id = ?)
				",	
	delete_location_map =>	"	DELETE 	FROM vd_mapping

					WHERE 	(location_id = ?)
				",	
	add_location =>		"	INSERT	INTO locations
						(location)

					VALUES	(?)
				",				
	get_location_vds =>	"	SELECT	vd_map.id AS id,
						vd_map.vd_id AS vd_id,
						vd_map.location_id AS location_id,
						vd.name AS name,
						vd.description AS desc,
						vd.description_long AS desc_long,
						l.location AS location			

					FROM	vd_mapping vd_map
						INNER JOIN virtual_domains vd ON vd_map.vd_id = vd.id
						INNER JOIN locations l ON vd_map.location_id = l.id	
						
					WHERE	(l.location = ?)
				",
	delete_location_vd =>	"	DELETE 	FROM vd_mapping

					WHERE 	(vd_id = ?)
						AND (location_id = ?)
				",	
	add_location_vd =>	"	INSERT	INTO vd_mapping
						(vd_id, location_id)

					VALUES	(?, ?)
				",		
	get_vd =>		"	SELECT 	*

					FROM	virtual_domains
					
					WHERE	(name = ?)
				",
	get_location =>		"	SELECT 	*

					FROM	locations
					
					WHERE	(location = ?)
				",
	get_wlcs =>		"	SELECT 	*

					FROM	wlc

					WHERE 	NOT (name = 'unassociated')
				",
	get_aps =>		"	SELECT 	*

					FROM	aps
				",
	delete_ap =>		"	DELETE 	FROM aps

					WHERE 	(ethmac = ?)
				",	
	deactivate_ap =>	"	UPDATE	aps
	
					SET	updated = 'now()',
						active = 'false'
					
					WHERE 	(ethmac = ?)
				",	
	add_ap =>		"	INSERT	INTO aps
						(name, ethmac, wmac, serial, ip, model, location_id, 
						wlc_id, associated, uptime, neighbor_name, neighbor_addr,
						neighbor_port)

					VALUES	(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
				",
	update_ap =>		"	UPDATE	aps
	
					SET	name = (?),
						wmac = (?),
						serial = (?),
						ip = (?),
						model = (?),
						location_id = (?),
						wlc_id = (?),
						associated = (?),
						uptime = (?),
						neighbor_name = (?),
						neighbor_addr = (?),
						neighbor_port = (?),
						updated = 'now()',
						active = 'true'
						
					WHERE	(ethmac = ?)
				",
	add_count =>		"	INSERT 	INTO aps_count
						(type_id, count, type)
			
					SELECT	?, ?, ?
		
					WHERE	NOT EXISTS (
						SELECT	id
						FROM 	aps_count
						WHERE	(type_id = ?)
							AND (type = ?)
							AND (date = 'now()')
					);
				",
	get_vd_count =>		"	SELECT	vd.id,
						vd.name,
						COUNT(DISTINCT ap.id) AS count
					
					FROM	virtual_domains AS vd
						INNER JOIN vd_mapping vd_map	ON vd.id = vd_map.vd_id
						INNER JOIN locations loc	ON vd_map.location_id = loc.id
						INNER JOIN aps ap		ON loc.id = ap.location_id
						
					WHERE	(ap.active = 'true')
											
					GROUP BY vd.id, vd.name
				",
	get_wlc_count =>	"	SELECT	wlc.id,
						wlc.name,
						COUNT(DISTINCT ap.id) AS count
		
					FROM	wlc
						INNER JOIN aps ap	ON wlc.id = ap.wlc_id
						
					WHERE	(ap.associated = 'true')
						AND (ap.active = 'true')
			
					GROUP BY wlc.id, wlc.name
				",
	get_total_count =>	"	SELECT	COUNT(DISTINCT id) AS count

					FROM	aps
					
					WHERE	(active = 'true')
				",
	get_unassigned_aps =>	"	SELECT	aps.*,
						wlc.name AS wlc_name
						
					FROM	aps
						INNER JOIN locations AS l ON aps.location_id = l.id
						INNER JOIN wlc AS wlc ON aps.wlc_id = wlc.id
						
					WHERE	(l.location = 'Root Area')
						AND (aps.active = true)
				",
	get_unassociated_aps =>	"	SELECT	aps.*,
						l.location AS location_name
						
					FROM	aps
						INNER JOIN locations AS l ON aps.location_id = l.id
						
					WHERE	(aps.associated = false)
						AND (aps.active = true)
						AND (aps.model NOT LIKE '%OEAP%')
						AND (l.location NOT LIKE '%HBE > Utlan%')
	",
	get_rootdomain_aps =>	"	SELECT	aps.ethmac,
						aps.name,
						aps.ip,
						aps.model,
						aps.neighbor_name,
						aps.neighbor_addr,
						aps.neighbor_port,
						wlc.name AS wlc_name,
						wlc.ipv4 AS wlc_ipv4,
						l.location AS location_name
						
					FROM	aps
						INNER JOIN locations AS l ON aps.location_id = l.id
						INNER JOIN wlc AS wlc ON aps.wlc_id = wlc.id
						INNER JOIN vd_mapping AS vd_map ON aps.location_id = vd_map.location_id
						INNER JOIN virtual_domains AS vd ON vd_map.vd_id = vd.id
						
					WHERE	(aps.active = true)
						AND NOT (l.location = 'Root Area')

					GROUP BY aps.ethmac,
						aps.name,
						aps.ip,
						aps.model,
						aps.neighbor_name,
						aps.neighbor_addr,
						aps.neighbor_port,
						wlc_name,
						wlc_ipv4,
						location_name

					HAVING COUNT(aps.ethmac) = 1
	",
	get_active_aps =>	"	SELECT 	aps.*,
						wlc.name AS wlc_name,
						wlc.ipv4 AS wlc_ipv4,
						l.location AS location_name

					FROM	aps
						INNER JOIN locations AS l ON aps.location_id = l.id
						INNER JOIN wlc AS wlc ON aps.wlc_id = wlc.id

					WHERE 	(aps.active = true)
				",
	get_specific_subnet =>	"	SELECT 	aps.*,
						wlc.name AS wlc_name,
						wlc.ipv4 AS wlc_ipv4,
						l.location AS location_name

					FROM	aps
						INNER JOIN locations AS l ON aps.location_id = l.id
						INNER JOIN wlc AS wlc ON aps.wlc_id = wlc.id

					WHERE 	(aps.active = true)
						AND (aps.ip << ?)
				",				
	get_graph_wlc_all =>	"	SELECT 	wlc.name, extract(epoch from count.date) AS date, count.count

					FROM 	aps_count AS count
						INNER JOIN wlc ON wlc.id = count.type_id
						
					WHERE	count.date >= to_timestamp(?)
						AND count.date <= to_timestamp(?)
						AND count.type = 'wlc'
				",
	get_graph_wlc_week =>	"	(SELECT DISTINCT ON (date_week, count.type_id)
						wlc.name, extract(epoch from count.date) AS date, count.count,
						date_trunc('week', count.date) AS date_week

					FROM 	aps_count AS count
						INNER JOIN wlc ON wlc.id = count.type_id

					WHERE	count.date >= to_timestamp(?)
						AND count.date <= to_timestamp(?)
						AND count.type = 'wlc'
						
					ORDER BY date_week, count.type_id, date)
					
					UNION ALL
					
					(SELECT DISTINCT ON (wlc.name)
				       		wlc.name, extract(epoch from count.date) AS date, count.count,
						date_trunc('week', count.date) AS date_week
				
					FROM 	aps_count AS count
						INNER JOIN wlc ON wlc.id = count.type_id
						
					WHERE	count.type = 'wlc'

					ORDER  BY wlc.name, date DESC)
				",
	get_graph_vd_all =>	"	SELECT 	vd.description, extract(epoch from count.date) AS date, count.count

					FROM 	aps_count AS count
						INNER JOIN virtual_domains AS vd ON vd.id = count.type_id

					WHERE	count.date >= to_timestamp(?)
						AND count.date <= to_timestamp(?)
						AND count.type = 'vd'
				",
	get_graph_vd_week =>	"	(SELECT DISTINCT ON (date_week, count.type_id)
						vd.description, extract(epoch from count.date) AS date, count.count,
						date_trunc('week', count.date) AS date_week

					FROM 	aps_count AS count
						INNER JOIN virtual_domains AS vd ON vd.id = count.type_id

					WHERE	count.date >= to_timestamp(?)
						AND count.date <= to_timestamp(?)
						AND count.type = 'vd'

					ORDER BY date_week, count.type_id, date)

					UNION ALL

					(SELECT DISTINCT ON (vd.description)
				       		vd.description, extract(epoch from count.date) AS date, count.count,
						date_trunc('week', count.date) AS date_week

					FROM 	aps_count AS count
						INNER JOIN virtual_domains AS vd ON vd.id = count.type_id
						
					WHERE	count.type = 'vd'

					ORDER  BY vd.description, date DESC)
				",
	get_graph_total =>	"	SELECT	id, extract(epoch from date) AS date, count

					FROM 	aps_count
					
					WHERE	date >= to_timestamp(?)
						AND date <= to_timestamp(?)
						AND type = 'total'
				",
	update_uptime =>	"	UPDATE	aps
	
					SET	uptime = (?),
						updated = 'now()'
						
					WHERE	(ethmac = ?)
				",
	update_alarm =>		"	UPDATE	aps
	
					SET	alarm = (?),
						updated = 'now()'
						
					WHERE	(wmac = ?)
				",
	reset_alarms =>		"	UPDATE	aps
	
					SET	alarm = 'undef',
						updated = 'now()'
					
					WHERE	active = true
				",
	update_apgroup_info =>	"	UPDATE	aps
	
					SET	apgroup_name = (?),
						ap_oid = (?),
						updated = 'now()'
						
					WHERE	(ethmac = ?)
				",
	update_apgroup =>	"	UPDATE	aps
	
					SET	apgroup_name = (?),
						updated = 'now()'
						
					WHERE	(ethmac = ?)
				",
	get_apinfo =>		"	SELECT 	aps.*,
						wlc.name AS wlc_name,
						wlc.ipv4 AS wlc_ipv4,
						wlc.snmp_ro AS wlc_snmp_ro,
						wlc.snmp_rw AS wlc_snmp_rw,
						l.location AS location_name

					FROM	aps
						INNER JOIN locations AS l ON aps.location_id = l.id
						INNER JOIN wlc AS wlc ON aps.wlc_id = wlc.id

					WHERE 	(aps.ethmac = ?)
				",
	empty_aps_diff =>	"	TRUNCATE TABLE aps_diff
				",
	add_aps_diff =>		"	INSERT	INTO aps_diff
						(name, ethmac, wlc_name, db_wlc_name, apgroup_name, db_apgroup_name)
						
					VALUES	(?, ?, ?, ?, ?, ?)
				",
	get_aps_diff =>		"	SELECT	*
	
					FROM	aps_diff
				",
	add_log =>		"	INSERT	INTO log
						(ap_id, username, caseid, message)
						
					VALUES	(?, ?, ?, ?)
				",
	get_missing_cdp_aps =>	"	SELECT	aps.*,
						wlc.name AS wlc_name
			
					FROM	aps
						INNER JOIN locations AS l ON aps.location_id = l.id
						INNER JOIN wlc AS wlc ON aps.wlc_id = wlc.id
			
					WHERE	(aps.active = true)
						AND (aps.associated = true)
						AND (aps.neighbor_name = '')
						AND aps.model not like '%OEAP%'
				",
};

# Create class
sub new{
	my $self = {};
	my ($class, $args) = @_;

	unless($args->{disable_log}){
		my $logfile_name = $config{path}->{log_folder} . "/" . date_string_ymd();
		
		open $LOG_FILE, '>>', $logfile_name or die "Couldn't open $logfile_name: $!";
	}
	
	return bless $self, $class;
}

# Logs stuff to file and STDOUT or STDERR
sub log_stuff{
	if ($_[0] =~ m/HASH/){
		#Value is a reference on an anonymous hash
		shift; # Remove class that is passed to the subroutine
	}
	
	my $script = shift;
	my $stderr = shift;
	
	print $LOG_FILE date_string() . ": [$script] @_\n";
	unless ($silent_logging){
		if($stderr){
			print STDERR date_string() . ": [$script] @_\n";
		} else {
			print date_string() . ": [$script] @_\n";
		}
	}
}


# Logs normal stuff
sub log_it{
	if ($_[0] =~ m/HASH/){
		#Value is a reference on an anonymous hash
		shift; # Remove class that is passed to the subroutine
	}	
	
	log_stuff(shift, 0, "@_");
}

# Logs debug-stuff if debug has been turned on
sub debug_log{
	if ($_[0] =~ m/HASH/){
		#Value is a reference on an anonymous hash
		shift; # Remove class that is passed to the subroutine
	}

	if ($config{switch}->{debug_log}){
		log_stuff(shift, 0, "Debug: @_");
	}
}

# Logs error-stuff
sub error_log{
	if ($_[0] =~ m/HASH/){
		#Value is a reference on an anonymous hash
		shift; # Remove class that is passed to the subroutine
	}

	log_stuff(shift, 1, "Error: @_");
}

sub enable_silent_logging{
	$silent_logging = 1;
}

# Returns RFC822-formatted date-string
sub date_string{
	return POSIX::strftime("%a, %d %b %Y %H:%M:%S %z", localtime(time()));
}

# Returns YYYY/MM
sub date_string_ym{
	return POSIX::strftime("%Y-%m", localtime(time()));
}

# Returns YYYY-MM-DD
sub date_string_ymd{
	return POSIX::strftime("%Y-%m-%d", localtime(time()));
}

# Returns YYYY-MM-DD HH
sub date_string_ymdh{
	return POSIX::strftime("%Y-%m-%d %H", localtime(time()));
}

# Fetch config-values
sub get_config{
	return %config;
}

# Connect to database
sub connect{
	my $self = shift;
	
	#if (pingable($config{db}->{hostname})){
	if (1){
		my $connect_string = "DBI:Pg:";
		$connect_string .= "dbname=$config{db}->{database};";
		$connect_string .= "host=$config{db}->{hostname};";
		$connect_string .= "port=$config{db}->{port};";
		$connect_string .= "sslmode=require";
		
		$self->{_dbh} = DBI->connect(	$connect_string,
						$config{db}->{username},
						$config{db}->{password}, 
						{
							'RaiseError' => 0,
							'AutoInactiveDestroy' => 1,
							'pg_enable_utf8' => -1,
						}) 
			or die error_log("aplol", "Got error $DBI::errstr when connecting to database.");
	} else {
		error_log("aplol", "Could not ping database-server.");
		exit 1;
	}
}

# Disconnect from database
sub disconnect{
	my $self = shift;
	$self->{_dbh}->disconnect();
}


# fetch PI API content
sub get_url{
        my $url = shift;
        my $full_url = $config{ciscopi}->{baseurl} . "/" . $url;

	$ENV{PERL_LWP_SSL_VERIFY_HOSTNAME} = 0; # just to be sure :-D
	my $ua = LWP::UserAgent->new(proxy => '');
	my $req = HTTP::Request->new(GET => $full_url);
	$req->authorization_basic($config{ciscopi}->{username}, $config{ciscopi}->{password});
	
	my $res = $ua->request($req);
	my $content = $res->content();
	my $header_info = "Status code: " . $res->status_line() . ". Content type: " . $res->content_type();
	
	return ($content, $header_info);
}

# get JSON from PI
sub get_json{
	use JSON;
	use LWP 5.64;
	use LWP::UserAgent;
	use Net::SSL; # needed, else LWP goes into emo-mode
	use Try::Tiny;
	
	my $self = shift;
	my $url = shift;
	my $json = new JSON;
	my $newurl = $url;
	my @json_content;

	while(1){
		# iterate through all pagings until done
		my ($url_content, $header_info) = get_url($newurl);
	
		if($url_content){
			my $json_text;
			try {
				$json_text = $json->allow_nonref->utf8->relaxed->escape_slash->loose->allow_singlequote->allow_barekey->decode($url_content);
			} catch {
				use Data::Dumper;
				print Dumper($url_content);
				error_log("get-json", $header_info);
				die(error_log("get-json", "Malformed output from \$url_content; '$newurl'"));
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
				die(error_log("get-json", "Wrong 'first' and 'count' in JSON."));
			}
		} else {
			die(error_log("get-json", "No content returned from get_url()."));
		}
	}
	
	return \@json_content;
}

# Get all VD's
sub get_vds{
	my $self = shift;
	
	$self->{_sth} = $self->{_dbh}->prepare($sql_statements->{get_vds});
	$self->{_sth}->execute();
	
	my $vds = $self->{_sth}->fetchall_hashref("name");
	$self->{_sth}->finish();
	
	return $vds;
}

# Delete VD
sub delete_vd{
	my $self = shift;
	my $vd = "@_";
	
	$self->{_sth} = $self->{_dbh}->prepare($sql_statements->{delete_vd});
	$self->{_sth}->execute($vd);
	$self->{_sth}->finish();
}

# Add VD
sub add_vd{
	my $self = shift;
	my ($vd, $description) = @_;
	
	$self->{_sth} = $self->{_dbh}->prepare($sql_statements->{add_vd});
	$self->{_sth}->execute($vd, $description);
	$self->{_sth}->finish();
}

# Get all locations
sub get_locations{
	my $self = shift;
	
	$self->{_sth} = $self->{_dbh}->prepare($sql_statements->{get_locations});
	$self->{_sth}->execute();
	
	my $locations = $self->{_sth}->fetchall_hashref("location");
	$self->{_sth}->finish();
	
	return $locations;
}

# Delete location
sub delete_location{
	my $self = shift;
	my $location_id = "@_";
	
	# delete all mappings
	$self->{_sth} = $self->{_dbh}->prepare($sql_statements->{delete_location_map});
	$self->{_sth}->execute($location_id);
	$self->{_sth}->finish();
	
	# then delete actual location
	$self->{_sth} = $self->{_dbh}->prepare($sql_statements->{delete_location});
	$self->{_sth}->execute($location_id);
	$self->{_sth}->finish();
}

# Add location
sub add_location{
	my $self = shift;
	my $location = "@_";
		
	$self->{_sth} = $self->{_dbh}->prepare($sql_statements->{add_location});
	$self->{_sth}->execute($location);
	$self->{_sth}->finish();
}

# Get all VD's for a location
sub get_location_vds{
	my $self = shift;
	my $location = "@_";
	
	$self->{_sth} = $self->{_dbh}->prepare($sql_statements->{get_location_vds});
	$self->{_sth}->execute($location);
	
	my $vds = $self->{_sth}->fetchall_hashref("name");
	$self->{_sth}->finish();
	
	return $vds;
}

# Delete VD for location
sub delete_location_vd{
	my $self = shift;
	my ($vd_id, $location_id) = @_;
	
	$self->{_sth} = $self->{_dbh}->prepare($sql_statements->{delete_location_vd});
	$self->{_sth}->execute($vd_id, $location_id);
	$self->{_sth}->finish();
}

# Add VD for location
sub add_location_vd{
	my $self = shift;
	my ($vd, $location) = @_;
	
	my $vd_item = get_vd($self, $vd);
	my $location_item = get_location($self, $location);
	my $vd_id = $vd_item->{id};
	my $location_id = $location_item->{id};
	
	$self->{_sth} = $self->{_dbh}->prepare($sql_statements->{add_location_vd});
	$self->{_sth}->execute($vd_id, $location_id);
	$self->{_sth}->finish();
}

# Get all info about VD
sub get_vd{
	my $self = shift;
	my $vd = "@_";
	
	$self->{_sth} = $self->{_dbh}->prepare($sql_statements->{get_vd});
	$self->{_sth}->execute($vd);
	
	my $vd_item = $self->{_sth}->fetchrow_hashref();
	$self->{_sth}->finish();
		
	return $vd_item;
}

# Get all info for Location
sub get_location{
	my $self = shift;
	my $location = "@_";
	
	$self->{_sth} = $self->{_dbh}->prepare($sql_statements->{get_location});
	$self->{_sth}->execute($location);
	
	my $location_item = $self->{_sth}->fetchrow_hashref();
	$self->{_sth}->finish();
	
	return $location_item;
}

# Get all WLC's
sub get_wlcs{
	my $self = shift;
	
	$self->{_sth} = $self->{_dbh}->prepare($sql_statements->{get_wlcs});
	$self->{_sth}->execute();
	
	my $wlcs = $self->{_sth}->fetchall_hashref("name");
	$self->{_sth}->finish();
	
	return $wlcs;
}

# Get all AP's
sub get_aps{
	my $self = shift;
	
	$self->{_sth} = $self->{_dbh}->prepare($sql_statements->{get_aps});
	$self->{_sth}->execute();
	
	my $aps = $self->{_sth}->fetchall_hashref("ethmac");
	$self->{_sth}->finish();
	
	return $aps;
}

# Delete AP
sub delete_ap{
	my $self = shift;
	my $ethmac = "@_";
	
	$self->{_sth} = $self->{_dbh}->prepare($sql_statements->{delete_ap});
	$self->{_sth}->execute($ethmac);
	$self->{_sth}->finish();
}

# Deactivate AP
sub deactivate_ap{
	my $self = shift;
	my $ethmac = "@_";
	
	$self->{_sth} = $self->{_dbh}->prepare($sql_statements->{deactivate_ap});
	$self->{_sth}->execute($ethmac);
	$self->{_sth}->finish();
}

# Add AP
sub add_ap{
	my $self = shift;
	my $apinfo = shift;
	
	$self->{_sth} = $self->{_dbh}->prepare($sql_statements->{add_ap});
	$self->{_sth}->execute(	$apinfo->{name},
				$apinfo->{ethmac},
				$apinfo->{wmac},
				$apinfo->{serial},
				$apinfo->{ip},
				$apinfo->{model},
				$apinfo->{location_id},
				$apinfo->{wlc_id},
				$apinfo->{associated},
				$apinfo->{uptime},
				$apinfo->{neighbor_name},
				$apinfo->{neighbor_addr},
				$apinfo->{neighbor_port}
				);
	$self->{_sth}->finish();
	
	# add client count
	add_client_count($self, $apinfo);
}

# Update AP
sub update_ap{
	my $self = shift;
	my $apinfo = shift;
	
	$self->{_sth} = $self->{_dbh}->prepare($sql_statements->{update_ap});
	$self->{_sth}->execute(	$apinfo->{name},
				$apinfo->{wmac},
				$apinfo->{serial},
				$apinfo->{ip},
				$apinfo->{model},
				$apinfo->{location_id},
				$apinfo->{wlc_id},
				$apinfo->{associated},
				$apinfo->{uptime},
				$apinfo->{neighbor_name},
				$apinfo->{neighbor_addr},
				$apinfo->{neighbor_port},
				$apinfo->{ethmac}
				);
	$self->{_sth}->finish();
	
	# add client count
	add_client_count($self, $apinfo);
}

# Add client count
sub add_client_count{
	my $self = shift;
	my $apinfo = shift;
	my $date_like = '\'%' . date_string_ymdh() . '%\'';
	
	# only add one entry per AP per hour
	# TODO: this needs to be fixed... :-D
	my $add_client_count_query = qq(
INSERT	INTO aps_clients
	(ap_id, type, count)
					
VALUES	( (SELECT id FROM aps WHERE ethmac = ?), '2.4GHz', ? ),
	( (SELECT id FROM aps WHERE ethmac = ?), '5GHz', ? ),
	( (SELECT id FROM aps WHERE ethmac = ?), 'Total', ? )

WHERE	NOT EXISTS (
	SELECT	id
	FROM 	aps_clients
	WHERE	date::text LIKE $date_like
		AND (ethmac = ?)
)
);

	$self->{_sth} = $self->{_dbh}->prepare($add_client_count_query);
	$self->{_sth}->execute( $apinfo->{ethmac},
				$apinfo->{client_24},
				$apinfo->{ethmac},
				$apinfo->{client_5},
				$apinfo->{ethmac},
				$apinfo->{client_total},
				$apinfo->{ethmac}
				);
	$self->{_sth}->finish();
}

# Add count
sub add_count{
	my $self = shift;
	my ($id, $count, $type) = @_;
	
	$self->{_sth} = $self->{_dbh}->prepare($sql_statements->{add_count});
	$self->{_sth}->execute($id, $count, $type, $id, $type);
	$self->{_sth}->finish();
}

# Get AP-count for each VD
sub get_vd_count{
	my $self = shift;
	
	$self->{_sth} = $self->{_dbh}->prepare($sql_statements->{get_vd_count});
	$self->{_sth}->execute();
	
	my $vd_count = $self->{_sth}->fetchall_hashref("id");
	$self->{_sth}->finish();
	
	return $vd_count;
}

# Get WLC-count
sub get_wlc_count{
	my $self = shift;
	
	$self->{_sth} = $self->{_dbh}->prepare($sql_statements->{get_wlc_count});
	$self->{_sth}->execute();
	
	my $wlc_count = $self->{_sth}->fetchall_hashref("id");
	$self->{_sth}->finish();
	
	return $wlc_count;
}

# Get total count
sub get_total_count{
	my $self = shift;
	
	$self->{_sth} = $self->{_dbh}->prepare($sql_statements->{get_total_count});
	$self->{_sth}->execute();
	
	my $total_count = ($self->{_sth}->fetchrow_array)[0];
	$self->{_sth}->finish();
	
	return $total_count;
}

# Insert total count (but only if it doesn't exist already)
# I.e. we only want one entry per day
sub add_total_count{
	my $self = shift;
	my $total_count = shift;
	my $date_like = '\'%' . date_string_ym() . '%\'';
	
	# only add one entry per day
	my $add_total_query = qq(
INSERT 	INTO aps_count
	(count, type)

SELECT	$total_count, 'total'

WHERE	NOT EXISTS (
	SELECT	id
	FROM 	aps_count
	WHERE	date::text LIKE $date_like
		AND type = 'total'
);
);

	$self->{_sth} = $self->{_dbh}->prepare($add_total_query);
	$self->{_sth}->execute();
	$self->{_sth}->finish();
}

# Get all unassigned AP's
sub get_unassigned_aps{
	my $self = shift;
	
	$self->{_sth} = $self->{_dbh}->prepare($sql_statements->{get_unassigned_aps});
	$self->{_sth}->execute();
	
	my $aps = $self->{_sth}->fetchall_hashref("ethmac");
	$self->{_sth}->finish();
	
	return $aps;
}

# Get all unassociated AP's
sub get_unassociated_aps{
	my $self = shift;
	
	$self->{_sth} = $self->{_dbh}->prepare($sql_statements->{get_unassociated_aps});
	$self->{_sth}->execute();
	
	my $aps = $self->{_sth}->fetchall_hashref("ethmac");
	$self->{_sth}->finish();
	
	return $aps;
}

# Get all AP's only member of ROOT-DOMAIN
# and not yet placed on a map
sub get_rootdomain_aps{
	my $self = shift;
	
	$self->{_sth} = $self->{_dbh}->prepare($sql_statements->{get_rootdomain_aps});
	$self->{_sth}->execute();
	
	my $aps = $self->{_sth}->fetchall_hashref("ethmac");
	$self->{_sth}->finish();
	
	return $aps;
}

# Get all active AP's
sub get_active_aps{
	my $self = shift;
	
	$self->{_sth} = $self->{_dbh}->prepare($sql_statements->{get_active_aps});
	$self->{_sth}->execute();
	
	my $aps = $self->{_sth}->fetchall_hashref("ethmac");
	$self->{_sth}->finish();
	
	return $aps;
}

# Get all AP's of specific model
sub get_specific_model{
	my $self = shift;
	my $model = shift;
	my $model_like = '\'%' . $model . '%\'';
	
	my $specific_model_query = qq(
SELECT 	aps.*,
	wlc.name AS wlc_name,
	l.location AS location_name

FROM	aps
	INNER JOIN locations AS l ON aps.location_id = l.id
	INNER JOIN wlc AS wlc ON aps.wlc_id = wlc.id

WHERE 	aps.active = true
	AND aps.model LIKE $model_like
);

	$self->{_sth} = $self->{_dbh}->prepare($specific_model_query);
	$self->{_sth}->execute();
	
	my $aps = $self->{_sth}->fetchall_hashref("ethmac");
	$self->{_sth}->finish();
	
	return $aps;
}

# Get all AP's with IP's in a specific subnet
sub get_specific_subnet{
	my $self = shift;
	my $subnet = shift;

	$self->{_sth} = $self->{_dbh}->prepare($sql_statements->{get_specific_subnet});
	$self->{_sth}->execute($subnet);
	
	my $aps = $self->{_sth}->fetchall_hashref("ethmac");
	$self->{_sth}->finish();
	
	return $aps;
}

# Get all total counts
sub get_graph_total{
	my $self = shift;
	my ($start, $end) = @_;
	
	$self->{_sth} = $self->{_dbh}->prepare($sql_statements->{get_graph_total});
	$self->{_sth}->execute($start, $end);
	
	my $count = $self->{_sth}->fetchall_hashref("id");
	$self->{_sth}->finish();
	
	return $count;
}

# Get all WLC counts for all WLCs
sub get_graph_wlc_all{
	my $self = shift;
	my ($start, $end) = @_;
	
	if(($end - $start) > (3 * 31 * 24 * 60 * 60)){
		# if more than 3 months, load weekly data
		$self->{_sth} = $self->{_dbh}->prepare($sql_statements->{get_graph_wlc_week});
	} else {
		$self->{_sth} = $self->{_dbh}->prepare($sql_statements->{get_graph_wlc_all});
	}
	
	$self->{_sth}->execute($start, $end);
	
	my $count = $self->{_sth}->fetchall_arrayref({});
	$self->{_sth}->finish();
	
	return $count;
}

# Get all VD counts for all VDs
sub get_graph_vd_all{
	my $self = shift;
	my ($start, $end) = @_;
	
	if(($end - $start) > (3 * 31 * 24 * 60 * 60)){
		# if more than 3 months, load weekly data
		$self->{_sth} = $self->{_dbh}->prepare($sql_statements->{get_graph_vd_week});
	} else {
		$self->{_sth} = $self->{_dbh}->prepare($sql_statements->{get_graph_vd_all});
	}
	
	$self->{_sth}->execute($start, $end);
	
	my $count = $self->{_sth}->fetchall_arrayref({});
	$self->{_sth}->finish();
	
	return $count;
}

# Update uptime
sub update_uptime{
	my $self = shift;
	my ($ethmac, $uptime) = @_;
	
	$self->{_sth} = $self->{_dbh}->prepare($sql_statements->{update_uptime});
	$self->{_sth}->execute($uptime, $ethmac);
	$self->{_sth}->finish();
}

# Update alarm
sub update_alarm{
	my $self = shift;
	my ($wmac, $alarm) = @_;
	
	$self->{_sth} = $self->{_dbh}->prepare($sql_statements->{update_alarm});
	$self->{_sth}->execute($alarm, $wmac);
	$self->{_sth}->finish();
}

# Set all alarms to 'undef'
sub reset_alarms{
	my $self = shift;
	
	$self->{_sth} = $self->{_dbh}->prepare($sql_statements->{reset_alarms});
	$self->{_sth}->execute();
	$self->{_sth}->finish();
}

# Update AP-group-info (apgroup + OID)
sub update_apgroup_info{
	my $self = shift;
	my ($ethmac, $apgroup_name, $ap_oid) = @_;
	
	$self->{_sth} = $self->{_dbh}->prepare($sql_statements->{update_apgroup_info});
	$self->{_sth}->execute($apgroup_name, $ap_oid, $ethmac);
	$self->{_sth}->finish();
}

# Update only AP-group
sub update_apgroup{
	my $self = shift;
	my ($ethmac, $apgroup_name) = @_;
	
	$self->{_sth} = $self->{_dbh}->prepare($sql_statements->{update_apgroup});
	$self->{_sth}->execute($apgroup_name, $ethmac);
	$self->{_sth}->finish();
}

# returns apinfo for single AP
# based on ethmac
sub get_apinfo{
	my $self = shift;
	my $ethmac = shift;
	
	$self->{_sth} = $self->{_dbh}->prepare($sql_statements->{get_apinfo});
	$self->{_sth}->execute($ethmac);
	
	my $apinfo = $self->{_sth}->fetchrow_hashref();
	$self->{_sth}->finish();
	
	return $apinfo;
}

# check if array contains entry
sub array_contains{
	my $self = shift;
	my ($array, $value) = @_;
	
	foreach my $element (@$array){
		return 1 if($element =~ m/$value/);
	}
	
	return 0;
}

# Empty aps_diff table
sub empty_aps_diff{
	my $self = shift;
	
	$self->{_sth} = $self->{_dbh}->prepare($sql_statements->{empty_aps_diff});
	$self->{_sth}->execute();
	$self->{_sth}->finish();
}

# Add AP to aps_diff table
sub add_aps_diff{
	my $self = shift;
	my($ethmac, $apname, $wlc_apgroup, $db_apgroup, $wlc_name, $db_wlc_name) = @_;
	
	$self->{_sth} = $self->{_dbh}->prepare($sql_statements->{add_aps_diff});
	$self->{_sth}->execute($apname, $ethmac, $wlc_name, $db_wlc_name, $wlc_apgroup, $db_apgroup);
	$self->{_sth}->finish();
}

# Get all AP's from aps_diff table
sub get_aps_diff{
	my $self = shift;
	
	$self->{_sth} = $self->{_dbh}->prepare($sql_statements->{get_aps_diff});
	$self->{_sth}->execute();
	
	my $aps = $self->{_sth}->fetchall_hashref("ethmac");
	$self->{_sth}->finish();
	
	return $aps;
}

# Insert log entry
sub add_log{
	my $self = shift;
	my ($ap_id, $username, $caseid, $message) = @_;
	
	$self->{_sth} = $self->{_dbh}->prepare($sql_statements->{add_log});
	$self->{_sth}->execute($ap_id, $username, $caseid, $message);
	$self->{_sth}->finish();
}

# Get AP's with missing CDP-info
sub get_missing_cdp_aps{
	my $self = shift;
	
	$self->{_sth} = $self->{_dbh}->prepare($sql_statements->{get_missing_cdp_aps});
	$self->{_sth}->execute();
	
	my $aps = $self->{_sth}->fetchall_hashref("ethmac");
	$self->{_sth}->finish();
	
	return $aps;
}


