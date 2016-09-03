#!/usr/bin/perl
# From command-line;
#     https_proxy= HTTPS_PROXY= perl aplol-ciscopi-aps.pl
use warnings;
use strict;
use POSIX qw(strftime);
use POSIX qw(floor);
use JSON -support_by_pp;
use LWP 5.64;
use LWP::UserAgent;
use Net::SSL; # needed, else LWP goes into emo-mode
use Fcntl qw(:flock);
use Try::Tiny;
use Date::Parse;
use Scalar::Util qw/reftype/;
binmode(STDOUT, ":utf8");

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
	$aplol->log_it("ciscopi-apinfo", "@_");
}

# Logs debug-stuff if debug has been turned on
sub debug_log{
	$aplol->debug_log("ciscopi-apinfo", "@_");
}

# Logs error-stuff
sub error_log{
	$aplol->error_log("ciscopi-apinfo", "@_");
}

# Shows runtime
sub show_runtime{
	my $runtime = time() - $time_start;
	log_it("Took $runtime seconds to complete.");
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
				error_log($header_info);
				show_runtime();
				die(error_log("Malformed output from \$url_content; '$newurl'"));
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
				show_runtime();
				die(error_log("Wrong 'first' and 'count' in JSON."));
			}
		} else {
			show_runtime();
			die(error_log("No content returned from get_url()."));
		}
	}
	
	return \@json_content;
}

# fetch AP info
sub get_apinfo{
	my $vd = shift;
	my $url = "data/AccessPointDetails.json?.full=true&type=\"UnifiedAp\"&_ctx.domain=$vd";
	return get_json($url);
}

# fetch all APs
sub get_aps{
	my $vd = "ROOT-DOMAIN";
	my $pi_aps = get_apinfo($vd);
	my ($total, $total_with, $total_without);
	
	if($pi_aps){
		foreach my $apinfo (@$pi_aps){
			
			# next if DMZ-WLC
			if( $apinfo->{'accessPointDetailsDTO'}->{'unifiedApInfo'}->{'controllerName'} ){
				if( $apinfo->{'accessPointDetailsDTO'}->{'unifiedApInfo'}->{'controllerName'} =~ m/dmz/ ){
					next;
				}
			}
			
			# next if OEAP
			if( $apinfo->{'accessPointDetailsDTO'}->{'model'} =~ m/OEAP/ ){
				next;
			}
			
			# neighbor count
			my $neighbor_count = keys %{$apinfo->{'accessPointDetailsDTO'}->{'cdpNeighbors'}->{'cdpNeighbor'}};

			if($neighbor_count == 0){
				$total_without++;
			} else {
				$total_with++;
			}

			$total++;
		}
	}
	
	print "Total APs: $total\n";
	print "Total APs with CDP: $total_with\n";
	print "Total APs without CDP: $total_without\n";
}



# We only want 1 instance of this script running
# Check if already running -- if so, abort.
unless (flock(DATA, LOCK_EX|LOCK_NB)) {
	die("$0 is already running. Exiting.");
}

# connect
$time_start = time(); # set start time
$aplol->connect();

get_aps();

# disconnect
$aplol->disconnect();

# how long did it take?
show_runtime();


__DATA__
Do not remove. Makes sure flock() code above works as it should.
