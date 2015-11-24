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

# title
sub html_print{
	my ($title, $msg) = @_;
	
	return qq(
<h1>$title</h1>
<br />
<p>$msg</p>
);
	
}

# return select-list
sub html_selectform{
	my $active_apgroup = shift;
	my $html = "";

	foreach my $apgroup (@{$config{div}->{apgroups}}){
		if($active_apgroup =~ m/^$apgroup$/){
			# match
			$html .= qq(<option value="$apgroup" selected>$apgroup</option>);
			$html .= "\n";
		} else {
			# no match
			$html .= qq(<option value="$apgroup">$apgroup</option>);
			$html .= "\n";
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

my $ethmac = $cgi->param('ethmac');
my $action = $cgi->param('action');

# header
my $header = CGI::header(
	-type => 'text/html',
	-status => '200',
	-charset => 'utf-8'
);

my $html = $header;
$html .= qq(
<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Strict//EN" "http://www.w3.org/TR/xhtml1/DTD/xhtml1-strict.dtd">
<html xmlns="http://www.w3.org/1999/xhtml" xml:lang="en">
<head>
<title>Change AP-group</title>
<style type="text/css">
	\@import url(/css/index.css); 
</style>
</head>
<body>
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
					$tmp_html .= html_print("Select AP-group", "");
					$select_form = html_selectform($apinfo->{apgroup_name});
					$tmp_html .= qq(
<form name="apgroupform" action="apgroup.pl" method="get">
<select name="apgroup">
$select_form
</select>

<input type="hidden" value="$ethmac" name="ethmac" />
<input type="hidden" value="set" name="action" />

<input type="submit" value="Set">
</form>
<br />
<h2>List of affected AP's:</h2>
<div class="aplist">
<ul>
);
				}

				# add AP to list
				$tmp_html .= qq(<li>$apinfo->{name} ($apinfo->{location_name})</li>);
			} else {
				$tmp_html = html_print("Error", "No or incorrect arguments defined. Try again.");
				$failed = 1;
				last;
			}
		}

		unless($failed){
			$tmp_html .= qq(</ul>);
			$tmp_html .= qq(</div>);
		}
		$html .= $tmp_html;

	} elsif ($action =~ m/^set$/){
		# set AP-group
		my $apgroup = $cgi->param('apgroup');

		if($apgroup){
			if(valid_apgroup($apgroup)){
				# valid AP-group
				$html .= html_print("Set AP-group", "Changing AP-group to '$apgroup'.");
				$html .= qq(<div class="aplist">);
				$html .= qq(<ul>);

				foreach my $mac (split(',', $ethmac)){
					# for each mac
					my $apinfo = $aplol->get_apinfo($mac);

					if($apinfo){
						# only if we have valid info from DB
						my ($success, $errormsg) = set_apgroup($apinfo, $apgroup);

						if($success){
							# update DB
							$aplol->update_apgroup($mac, $apgroup);

							# print success
							$html .= qq(<li>Success: $apinfo->{name} ($apinfo->{location_name})</li>);							
						} else {
							$html .= qq(<li>Error: $apinfo->{name} ($apinfo->{location_name}), $errormsg</li>);	
						}
					} else {
						$html .= html_print("Error", "No or incorrect arguments defined. Try again.");
					}
				}
				$html .= qq(
</ul>
</div>
<br />
<div class="wrapper">
	<button class="button" type="button" onClick="window.location.replace('apgroup.html')">Return</button>
</div>);
			} else {
				$html .= html_print("Error", "No or invalid AP-group. Please try again.");
			}
		} else {
			$html .= html_print("Error", "No or incorrect arguments defined. Try again.");
		}
	} else {
		$html .= html_print("Error", "No or incorrect arguments defined. Try again.");
	}

	# done with DB
	$aplol->disconnect();
} else {
	$html .= html_print("Error", "No or incorrect arguments defined. Try again.");
}

# print footer
$html .= qq(
</body>
</html>
);

# print it all
print $html;

# done
exit 0;


__DATA__
Do not remove. Makes sure flock() code above works as it should.
