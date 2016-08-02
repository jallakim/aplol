#!/usr/bin/perl
use warnings;
use strict;
use Net::SNMP;
use Net::SNMP::Util;
use CGI;
use Fcntl qw(:flock);

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

# We only want 1 instance of this script running
# Check if already running -- if so, abort.
unless (flock(DATA, LOCK_EX|LOCK_NB)) {
        print "Script is already running. Exiting.";
	exit 1;
}

sub set_apgroup{
	my ($apinfo, $apgroup) = @_;

        my ($session, $error) = Net::SNMP->session(
                Hostname  => $apinfo->{wlc_ipv4},
                Community => $config{snmp}->{write},
		Version   => $config{snmp}->{version},
                Timeout   => $config{snmp}->{timeout},
                Retries   => $config{snmp}->{retries},
        );

        if ($session){
                my $write_result = $session->set_request(
                        -varbindlist => [$apinfo->{apgroup_oid}, OCTET_STRING, $apgroup]
                );
                                
                unless (keys %$write_result){
			$session->close();
			return (0, "Could not set new AP-group for ap '$apinfo->{name}'.");
                }
                
                $session->close();
		return 1;
        } else {
                $session->close();
		return (0, "Could not connect to $apinfo->{wlc_ipv4}: $error");
        }
}

# return select-list
sub html_selectform{
	my $active_apgroup = shift;
	my $html = "";

	foreach my $apgroup (@{$config{div}->{apgroups}}){
		if($active_apgroup =~ m/^$apgroup$/){
			# match
			$html .= qq(\t\t\t\t<option value="$apgroup" selected>$apgroup</option>\n);
		} else {
			# no match
			$html .= qq(\t\t\t\t<option value="$apgroup">$apgroup</option>\n);
		}
	}
	
	return ($html);
}

# return true if apgroup in array
sub valid_apgroup{
	my $apgroup = shift;

	foreach my $apgrp (@{$config{div}->{apgroups}}){
		if($apgroup =~ m/^$apgrp$/){
			return 1;
		}
	}

	# special groups that we don't want to show
	# but still be valid
	if($apgroup =~ m/^hvikt-oeap$/){
		return 1;
	}

	# not valid
	return 0;
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

	<title>Change AP group</title>

	<!-- Bootstrap core CSS -->
	<link href="/css/bootstrap.min.css" rel="stylesheet">

	<!-- IE10 viewport hack for Surface/desktop Windows 8 bug -->
	<link href="/css/ie10-viewport-bug-workaround.css" rel="stylesheet">

	<!-- Custom styles for this template -->
	<link href="/css/signin.css" rel="stylesheet">
</head>
<body>
	<div class="container">
		<form class="form-signin" name="apgroupform" action="apgroup.pl" method="get">
);

if ($ethmac && $action){
	# fetch data from DB
	$aplol->connect();

	if($action =~ m/^select$/){
		# select AP-group
		my $select_form; # pick group for the first AP in the list
		my $failed = 0;
		my $tmp_html;

		foreach my $mac (split(',', $ethmac)){
			# for each mac
			my $apinfo = $aplol->get_apinfo($mac);

			if($apinfo){
				# only if we have valid info from DB
			
				unless($select_form){
					#$tmp_html .= html_print("Select AP-group", "");
					my $apgroup = $apinfo->{apgroup_name};
					$select_form = html_selectform($apgroup);
					$tmp_html .= qq(
\t\t\t<h2 class="form-signin-heading">Change AP group</h2>
\t\t\t<select class="form-control" name="apgroup">
$select_form
\t\t\t</select>
\t\t\t<label for="inputCase" class="sr-only">Case ID</label>
\t\t\t<input name="caseid" type="text" id="inputCase" class="form-control" placeholder="Case ID" required>

\t\t\t<input type="hidden" value="$ethmac" name="ethmac" />
\t\t\t<input type="hidden" value="$apgroup" name="oldapgroup" />
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
		my $apgroup = $cgi->param('apgroup');
		my $oldapgroup = $cgi->param('oldapgroup');
		$oldapgroup = "undef" unless $oldapgroup;
		my $caseid = $cgi->param('caseid');
		
		if($apgroup && $username && $caseid){
			# have apgroup + username + caseid
			if(valid_apgroup($apgroup)){
				# valid AP-group
				
				my $failed = 0;
				my $tmp_html;
				
				$tmp_html = html_print("Set AP-group", "Changing AP-group to '$apgroup'.");
				$tmp_html .= qq(			
\t\t\t<br />
\t\t\t<button class="btn btn-lg btn-primary btn-block" type="button" onClick="window.location.replace('apgroup.html')">Return</button>
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
						my ($success, $errormsg) = set_apgroup($apinfo, $apgroup);

						if($success){
							# update DB
							$aplol->update_apgroup($mac, $apgroup);
							$aplol->add_log($apinfo->{id}, $username, $caseid, "AP-group changed from '$oldapgroup' to '$apgroup'.");

							# print success
							$tmp_html .= qq(\t\t\t\t<tr class="success"><td>$apinfo->{name}</td><td>$apinfo->{location_name}</td><td>-</td></tr>\n);							
						} else {
							$tmp_html .= qq(\t\t\t\t<tr class="danger"><td>$apinfo->{name}</td><td>$apinfo->{location_name}</td><td>$errormsg</td></tr>\n);
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
				$html .= html_print("Error", "No or invalid AP-group. Please try again.", 1);
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
