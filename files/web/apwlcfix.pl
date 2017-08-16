#!/usr/bin/perl
use warnings;
use strict;
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

# We only want 1 instance of this script running
# Check if already running -- if so, abort.
unless (flock(DATA, LOCK_EX|LOCK_NB)) {
        print "Script is already running. Exiting.";
	exit 1;
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
		<form class="form-signin" name="wlcform" action="apwlcfix.pl" method="post">
);

if ($ethmac && $action){
	# fetch data from DB
	$aplol->connect();

	if($action =~ m/^select$/){
		# select WLC
		my $failed = 0;
		my ($tmp_html, $form_printed);

		foreach my $ap (split(',', $ethmac)){
			# for each AP
			my ($mac, $new_wlc) = split(';', $ap);
			my $apinfo = $aplol->get_apinfo($mac);

			if($apinfo){
				# only if we have valid info from DB
			
				unless($form_printed){
					$form_printed = 1;
					$tmp_html .= qq(
\t\t\t<h2 class="form-signin-heading">Change WLC</h2>
\t\t\t<label for="inputCase" class="sr-only">Case ID</label>
\t\t\t<input name="caseid" type="text" id="inputCase" class="form-control" placeholder="Case ID" required>
\t\t\t<label>Reboot AP? &nbsp;&nbsp;<input name="reboot" type="checkbox" data-toggle="toggle" data-on="Yes" data-off="No" data-onstyle="danger"></label>

\t\t\t<input type="hidden" value="$ethmac" name="ethmac" />
\t\t\t<input type="hidden" value="set" name="action" />

\t\t\t<button class="btn btn-lg btn-primary btn-block" type="submit">Submit</button>

\t\t</form>
\t\t<br />
\t\t<table class="table table-striped table-sm">
\t\t\t<thead>
\t\t\t\t<tr>
\t\t\t\t\t<th class="col-md-2">AP-name</th>
\t\t\t\t\t<th class="col-md-3">Current WLC</th>
\t\t\t\t\t<th class="col-md-3">New WLC</th>
\t\t\t\t\t<th class="col-md-3">Location</th>
\t\t\t\t</tr>
\t\t\t</thead>
\t\t\t<tbody>
);
				}

				# add AP to list
				$tmp_html .= qq(\t\t\t\t<tr><td>$apinfo->{name}</td><td>$apinfo->{wlc_name}</td>);
				$tmp_html .= qq(<td>$new_wlc</td><td>$apinfo->{location_name}</td></tr>\n);
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
		# set WLC
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
		
		if($username && $caseid){
			# ethmac + username + caseid
			
			my $wlcs = $aplol->get_wlcs_name();
			
			my $failed = 0;
			my $tmp_html;
				
			$tmp_html = html_print("Set WLC", "Changing WLC for APs.");
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

			foreach my $ap (split(',', $ethmac)){
				# for each AP
				my ($mac, $new_wlc) = split(';', $ap);
				my $apinfo = $aplol->get_apinfo($mac);

				if($apinfo){
					# only if we have valid info from DB
					
					# set our new WLC as primary, and clear all other alternatives
					my ($error, $errormsg) = $aplol->set_ap_wlc($apinfo, $wlcs->{$new_wlc}, $reboot);

					if($error){
						$tmp_html .= qq(\t\t\t\t<tr class="danger"><td>$apinfo->{name}</td><td>$apinfo->{location_name}</td><td>$errormsg</td></tr>\n);
					} else {
						# update DB
						$aplol->add_log($apinfo->{id}, $username, $caseid, "WLC changed from '$apinfo->{wlc_name}' to '$new_wlc'.");

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
