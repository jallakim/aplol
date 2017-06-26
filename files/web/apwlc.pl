#!/usr/bin/perl
use warnings;
use strict;
use Net::SNMP;
use Net::SNMP::Util;
use Net::MAC;
use CGI;
use Fcntl qw(:flock);
binmode STDOUT, ":encoding(UTF-8)";

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

# variables
my $cgi = CGI->new();

my %oids = (
	# Reset the AP
	# bsnAPReset - 1.3.6.1.4.1.14179.2.2.1.1.11
	# http://snmp.cloudapps.cisco.com/Support/SNMP/do/BrowseOID.do?local=en&translate=Translate&objectInput=bsnAPReset#oidContent
	reset_ap => '1.3.6.1.4.1.14179.2.2.1.1.11.',
	
	# Primary WLC
	primary => {
		# Primary WLC; name
		# bsnAPPrimaryMwarName - 1.3.6.1.4.1.14179.2.2.1.1.10
		# http://snmp.cloudapps.cisco.com/Support/SNMP/do/BrowseOID.do?local=en&translate=Translate&objectInput=1.3.6.1.4.1.14179.2.2.1.1.10#oidContent
		name => '1.3.6.1.4.1.14179.2.2.1.1.10.',

		# Primary WLC; IP
		ip => {	
			# Primary WLC; IP type
			# cLApPrimaryControllerAddressType - 1.3.6.1.4.1.9.9.513.1.1.1.1.10
			# http://snmp.cloudapps.cisco.com/Support/SNMP/do/BrowseOID.do?local=en&translate=Translate&objectInput=1.3.6.1.4.1.9.9.513.1.1.1.1.10#oidContent
			type => '1.3.6.1.4.1.9.9.513.1.1.1.1.10.',

			# Primary WLC; IP address
			# cLApPrimaryControllerAddress - 1.3.6.1.4.1.9.9.513.1.1.1.1.11
			# http://snmp.cloudapps.cisco.com/Support/SNMP/do/BrowseOID.do?local=en&translate=Translate&objectInput=1.3.6.1.4.1.9.9.513.1.1.1.1.11#oidContent
			address => '1.3.6.1.4.1.9.9.513.1.1.1.1.11.',
		},
	},
	
	# Secondary WLC
	secondary => {
		# Secondary WLC; name
		# bsnAPSecondaryMwarName - 1.3.6.1.4.1.14179.2.2.1.1.23
		# http://snmp.cloudapps.cisco.com/Support/SNMP/do/BrowseOID.do?local=en&translate=Translate&objectInput=1.3.6.1.4.1.14179.2.2.1.1.23#oidContent
		name => '1.3.6.1.4.1.14179.2.2.1.1.23.',

		# Secondary WLC; IP
		ip => {	
			# Secondary WLC; IP type
			# cLApSecondaryControllerAddressType - 1.3.6.1.4.1.9.9.513.1.1.1.1.12
			# http://snmp.cloudapps.cisco.com/Support/SNMP/do/BrowseOID.do?local=en&translate=Translate&objectInput=1.3.6.1.4.1.9.9.513.1.1.1.1.12#oidContent
			type => '1.3.6.1.4.1.9.9.513.1.1.1.1.12.',

			# Secondary WLC; IP address
			# cLApSecondaryControllerAddress - 1.3.6.1.4.1.9.9.513.1.1.1.1.13
			# http://snmp.cloudapps.cisco.com/Support/SNMP/do/BrowseOID.do?local=en&translate=Translate&objectInput=1.3.6.1.4.1.9.9.513.1.1.1.1.13#oidContent
			address => '1.3.6.1.4.1.9.9.513.1.1.1.1.13.',
		},
	},
	
	# Tertiary WLC
	tertiary => {
		# Tertiary WLC; name
		# bsnAPTertiaryMwarName - 1.3.6.1.4.1.14179.2.2.1.1.24
		# http://snmp.cloudapps.cisco.com/Support/SNMP/do/BrowseOID.do?local=en&translate=Translate&objectInput=1.3.6.1.4.1.14179.2.2.1.1.24#oidContent
		name => '1.3.6.1.4.1.14179.2.2.1.1.24.',

		# Tertiary WLC; IP
		ip => {	
			# Tertiary WLC; IP type
			# cLApTertiaryControllerAddressType - 1.3.6.1.4.1.9.9.513.1.1.1.1.14
			# http://snmp.cloudapps.cisco.com/Support/SNMP/do/BrowseOID.do?local=en&translate=Translate&objectInput=1.3.6.1.4.1.9.9.513.1.1.1.1.14#oidContent
			type => '1.3.6.1.4.1.9.9.513.1.1.1.1.14.',

			# Tertiary WLC; IP address
			# cLApTertiaryControllerAddress - 1.3.6.1.4.1.9.9.513.1.1.1.1.15
			# http://snmp.cloudapps.cisco.com/Support/SNMP/do/BrowseOID.do?local=en&translate=Translate&objectInput=1.3.6.1.4.1.9.9.513.1.1.1.1.15#oidContent
			address => '1.3.6.1.4.1.9.9.513.1.1.1.1.15.',
		},
	},
);


# We only want 1 instance of this script running
# Check if already running -- if so, abort.
unless (flock(DATA, LOCK_EX|LOCK_NB)) {
        print "Script is already running. Exiting.";
	exit 1;
}

sub set_ap_wlc{
	my ($apinfo, $new_wlc, $reboot) = @_;

	if($apinfo->{associated} && $apinfo->{active}){
		# only allow this for associated and active APs
		
	        my ($session, $error) = Net::SNMP->session(
	                Hostname  => $apinfo->{wlc_ipv4},
	                Community => $apinfo->{wlc_snmp_rw},
			Version   => $config{snmp}->{version},
	                Timeout   => $config{snmp}->{timeout},
	                Retries   => $config{snmp}->{retries},
	        );

	        if ($session){
			my $mac = Net::MAC->new('mac' => $apinfo->{wmac});
			my $dec_mac = $mac->convert(
				'base' => 10,         # convert from base 16 to base 10
				'bit_group' => 8,     # octet grouping
				'delimiter' => '.'    # dot-delimited
			);	
			
			my $write_result = $session->set_request(
				-varbindlist => [
					$oids{primary}{name} . $dec_mac, OCTET_STRING, $new_wlc->{name},
					$oids{secondary}{name} . $dec_mac, OCTET_STRING, '',
					$oids{tertiary}{name} . $dec_mac, OCTET_STRING, '',

					$oids{primary}{ip}{type} . $dec_mac, INTEGER, 1,
					$oids{primary}{ip}{address} . $dec_mac, OCTET_STRING, octet_ipv4($new_wlc->{ipv4}),

					$oids{secondary}{ip}{type} . $dec_mac, INTEGER, 1,
					$oids{secondary}{ip}{address} . $dec_mac, OCTET_STRING, octet_ipv4('0.0.0.0'),

					$oids{tertiary}{ip}{type} . $dec_mac, INTEGER, 1,
					$oids{tertiary}{ip}{address} . $dec_mac, OCTET_STRING, octet_ipv4('0.0.0.0'),
				]
			);

			unless (keys %$write_result){
				my $error = $session->error();
				$session->close();
				return (1, "Could not set WLC: $error");
			}
						
			# new values set successfully
			# should we reboot?
			if($reboot){
				# reboot/restart the AP
				my $write_result = $session->set_request(
					-varbindlist => [
						$oids{reset_ap} . $dec_mac, INTEGER, 1
					]
				);

				unless (keys %$write_result){
					my $error = $session->error();
					$session->close();
					return (1, "Could not reboot AP: $error");
				}
			}
									
	                $session->close();
			return 0;
	        } else {
	                $session->close();
			return (1, "Could not connect to $apinfo->{wlc_ipv4}: $error");
	        }
	} else {
		return (1, "AP is not associated and/or active.");
	}
}

# returns octet string
sub octet_ipv4{
	my $ipv4 = shift;
	
	return pack("C*", split(/\./, $ipv4));
}

# return select-list
sub html_selectform{
	my $current_wlc = shift;
	my $html = "";

        my $wlcs = $aplol->get_wlcs();

	# iterate through all WLC's
	foreach my $wlc_name (sort keys %$wlcs){
		next if ($wlc_name =~ m/dmz/); # dont want DMZ
		
		if($current_wlc =~ m/^$wlc_name$/){
			# match
			$html .= qq(\t\t\t\t<option value="$wlc_name" selected>$wlc_name</option>\n);
		} else {
			# no match
			$html .= qq(\t\t\t\t<option value="$wlc_name">$wlc_name</option>\n);
		}
	}
	
	return ($html);
}

# header/error
sub html_print{
	my ($title, $msg, $error) = @_;

	my $error_tmp = '';
	$error_tmp = ' class="bg-danger"' if $error;

	return qq(
\t\t\t<h2>$title</h2>
\t\t\t<br />
\t\t\t<p$error_tmp>$msg</p>
);
       
}

my $ethmac = $cgi->param('ethmac');
my $action = $cgi->param('action');
my $username = $cgi->user_name(); # alternatively; $cgi->remote_user();

# header
my $header = CGI::header(
	-type => 'text/html',
	-status => '200',
	-charset => 'utf-8'
);

my $html = $header;
$html .= qq(<!DOCTYPE html>
<html lang="en">
<head>
	<meta charset="utf-8">
	<meta http-equiv="X-UA-Compatible" content="IE=edge">
	<meta name="viewport" content="width=device-width, initial-scale=1">
	<!-- The above 3 meta tags *must* come first in the head; any other head content must come *after* these tags -->
	<meta name="description" content="">
	<meta name="author" content="">

	<title>Change WLC</title>

	<!-- Bootstrap core CSS -->
	<link href="/css/bootstrap.min.css" rel="stylesheet">
		
	<!-- jQuery -->
	<script src="/js/jquery.js"></script>
		
	<!-- IE10 viewport hack for Surface/desktop Windows 8 bug -->
	<link href="/css/ie10-viewport-bug-workaround.css" rel="stylesheet">

	<!-- Custom styles for this template -->
	<link href="/css/signin.css" rel="stylesheet">
	
	<!-- Bootstrap Toggle -->
	<link href="/css/bootstrap-toggle.min.css" rel="stylesheet">
	<script src="/js/bootstrap-toggle.min.js"></script>
</head>
<body>
	<div class="container">
		<form class="form-signin" name="wlcform" action="apwlc.pl" method="post">
);

if ($ethmac && $action){
	# fetch data from DB
	$aplol->connect();

	if($action =~ m/^select$/){
		# select WLC
		my $select_form;
		my $failed = 0;
		my $tmp_html;

		foreach my $mac (split(',', $ethmac)){
			# for each mac
			my $apinfo = $aplol->get_apinfo($mac);

			if($apinfo){
				# only if we have valid info from DB
			
				unless($select_form){
					my $current_wlc = $apinfo->{wlc_name};
					$select_form = html_selectform($current_wlc);
					$tmp_html .= qq(
\t\t\t<h2 class="form-signin-heading">Change WLC</h2>
\t\t\t<select class="form-control" name="newwlc">
$select_form
\t\t\t</select>
\t\t\t<label for="inputCase" class="sr-only">Case ID</label>
\t\t\t<input name="caseid" type="text" id="inputCase" class="form-control" placeholder="Case ID" required>
\t\t\t<label>Reboot AP? &nbsp;&nbsp;<input name="reboot" type="checkbox" data-toggle="toggle" data-on="Yes" data-off="No" data-onstyle="danger"></label>

\t\t\t<input type="hidden" value="$ethmac" name="ethmac" />
\t\t\t<input type="hidden" value="$current_wlc" name="oldwlc" />
\t\t\t<input type="hidden" value="set" name="action" />

\t\t\t<button class="btn btn-lg btn-primary btn-block" type="submit">Submit</button>

\t\t</form>
\t\t<br />
\t\t<table class="table table-striped table-sm">
\t\t\t<thead>
\t\t\t\t<tr>
\t\t\t\t\t<th class="col-md-2">AP-name</th>
\t\t\t\t\t<th class="col-md-4">Location</th>
\t\t\t\t</tr>
\t\t\t</thead>
\t\t\t<tbody>
);
				}

				# add AP to list
				$tmp_html .= qq(\t\t\t\t<tr><td>$apinfo->{name}</td><td>$apinfo->{location_name}</td></tr>\n);
			} else {
				$tmp_html = html_print("Error", "No or incorrect arguments defined. Try again.", 1);
				$failed = 1;
				last;
			}
		}

		unless($failed){
			$tmp_html .= qq(\t\t\t</tbody>\n);
			$tmp_html .= qq(\t\t</table>);
		}
		$html .= $tmp_html;

	} elsif ($action =~ m/^set$/){
		# set AP-group
		my $new_wlc = $cgi->param('newwlc');
		my $old_wlc = $cgi->param('oldwlc');
		$old_wlc = "undef" unless $old_wlc;
		my $caseid = $cgi->param('caseid');
		
		# should we reboot the AP after setting the new WLC?
		my $reboot = $cgi->param('reboot');
		if($reboot){
			# defined
			if($reboot =~ m/on/){
				$reboot = 1;
			} else {
				$reboot = 0;
			}
		} else {
			$reboot = 0;
		}
		
		if($new_wlc && $username && $caseid){
			# have apgroup + username + caseid
			
			my $wlcs = $aplol->get_wlcs();
			
			if($wlcs->{$new_wlc}){
				# valid WLC
				
				my $failed = 0;
				my $tmp_html;
				
				$tmp_html = html_print("Set WLC", "Changing WLC to '$new_wlc'.");
				$tmp_html .= qq(			
\t\t\t<br />
\t\t\t<button class="btn btn-lg btn-primary btn-block" type="button" onClick="window.location.replace('/')">Return</button>
\t\t</form>
\t\t<br />
\t\t<table class="table table-striped table-sm">
\t\t\t<thead>
\t\t\t\t<tr>
\t\t\t\t\t<th class="col-md-2">AP-name</th>
\t\t\t\t\t<th class="col-md-4">Location</th>
\t\t\t\t\t<th class="col-md-2">Error</th>
\t\t\t\t</tr>
\t\t\t</thead>
\t\t\t<tbody>				
);

				foreach my $mac (split(',', $ethmac)){
					# for each mac
					my $apinfo = $aplol->get_apinfo($mac);

					if($apinfo){
						# only if we have valid info from DB
						
						# set our new WLC as primary, and clear all other alternatives
						my ($error, $errormsg) = set_ap_wlc($apinfo, $wlcs->{$new_wlc}, $reboot);

						if($error){
							$tmp_html .= qq(\t\t\t\t<tr class="danger"><td>$apinfo->{name}</td><td>$apinfo->{location_name}</td><td>$errormsg</td></tr>\n);
						} else {
							# update DB
							$aplol->add_log($apinfo->{id}, $username, $caseid, "WLC changed from '$old_wlc' to '$new_wlc'.");

							# print success
							$tmp_html .= qq(\t\t\t\t<tr class="success"><td>$apinfo->{name}</td><td>$apinfo->{location_name}</td><td>-</td></tr>\n);
						}
					} else {
						$tmp_html = html_print("Error", "No or incorrect arguments defined. Try again.", 1);
						$failed = 1;
						last;
					}
				}
				
				unless($failed){
					$tmp_html .= qq(
\t\t\t</tbody>
\t\t</table>
);
				}
				
				$html .= $tmp_html;
			} else {
				$html .= html_print("Error", "No or invalid WLC. Please try again.", 1);
			}
		} else {
			$html .= html_print("Error", "No or incorrect arguments defined. Try again.", 1);
		}
	} else {
		$html .= html_print("Error", "No or incorrect arguments defined. Try again.", 1);
	}

	# done with DB
	$aplol->disconnect();
} else {
	$html .= html_print("Error", "No or incorrect arguments defined. Try again.", 1);
}

# print footer
$html .= qq(
\t</div>
</body>
</html>
);

# print it all
print $html;

# done
exit 0;


__DATA__
Do not remove. Makes sure flock() code above works as it should.
