#!/usr/bin/perl
use warnings;
use strict;
use POSIX qw(strftime);
use POSIX qw(floor);
use JSON -support_by_pp;
use LWP 5.64;
use LWP::UserAgent;
use Date::Parse;
use Net::SSL; # needed, else LWP goes into emo-mode
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
	$aplol->log_it("ciscopi", "@_");
}

# Logs debug-stuff if debug has been turned on
sub debug_log{
	$aplol->debug_log("ciscopi", "@_");
}

# Logs error-stuff
sub error_log{
	$aplol->error_log("ciscopi", "@_");
}

# fetch PI API content
sub get_url{
        my $url = shift;
        my $full_url = $config{ciscopi}->{baseurl} . "/" . $url;

	$ENV{PERL_LWP_SSL_VERIFY_HOSTNAME} = 0; # just to be sure :-D
	my $ua = LWP::UserAgent->new(proxy => '');
	my $req = HTTP::Request->new(GET => $full_url);
	$req->authorization_basic($config{ciscopi}->{username}, $config{ciscopi}->{password});

	return $ua->request($req)->content();
}

# fetch AP info
sub get_apinfo{
        my $url = "data/AccessPoints.json?.full=true&.maxResults=9999";
        return get_url($url);
}

sub update_uptime{
	my $json = new JSON;
	my $json_content = get_apinfo();

	my $uptime;
	if($json_content){
		my $json_text = $json->allow_nonref->utf8->relaxed->escape_slash->loose->allow_singlequote->allow_barekey->decode($json_content);

		foreach my $apinfo (@{$json_text->{queryResponse}->{'entity'}}){
			my $ethmac = $apinfo->{'accessPointsDTO'}->{'ethernetMac'};
			next unless($ethmac);

			my $uptime = $apinfo->{'accessPointsDTO'}->{'upTime'};
			$uptime = 0 unless($uptime);

			# lets update DB
			debug_log("update uptime: $ethmac, $uptime");
			$aplol->update_uptime($ethmac, $uptime);
		}
	}
}

# fetch alarm info
sub get_alarminfo{
        my $severity = shift;
	my $url = "data/Alarms.json?.full=true&severity=$severity&acknowledgementStatus=false&.maxResults=9999";
        return get_url($url);
}

# fetch latest annotation
sub get_last_alarm_annotation{
        my $annotations = shift;

        if(defined($annotations)){
                foreach my $annotation_info (values %$annotations){
                        # $annotation_info is hash if only 1 value
                        # if multiple values, it's array of hashes

                        use Scalar::Util qw/reftype/;
                        if (reftype $annotation_info eq reftype {}) {
                                # hash, should be single value
                                # just return noteText
                                return ($annotation_info->{'noteText'}, $annotation_info->{'creationTimestamp'});
                        } else {
                                # assume array of hashes
                                # sort it first, and then pick most recent date

                                my @sorted = sort {     str2time($b->{'creationTimestamp'}) <=>
                                                        str2time($a->{'creationTimestamp'})}
                                                        @$annotation_info;

                                return ($sorted[0]->{'noteText'}, $sorted[0]->{'creationTimestamp'});
                        }
                }
        } else {
                # no annotations
                return ("undef", "1999-01-01 12:00:00");
        }
}

# get all alarms
sub update_alarms{
	my $severity = 'CRITICAL';
        my $json = new JSON;
        my $json_content = get_alarminfo($severity);

        if($json_content){
                my $json_text = $json->allow_nonref->utf8->relaxed->escape_slash->loose->allow_singlequote->allow_barekey->decode($json_content);

                # reset all alarms (so we don't get old in DB)
                $aplol->reset_alarms();

        	foreach my $alarm (@{$json_text->{queryResponse}->{'entity'}}){
                        if($alarm->{'alarmsDTO'}->{'category'}->{'value'} =~ m/^AP$/){
                                # Alarm-type is AP

                                # get last annotation
                                my ($alarm_annotation, $alarm_timestamp) = get_last_alarm_annotation($alarm->{'alarmsDTO'}->{'annotations'});
				if($alarm_annotation =~ m/^[0-9]+$/){
					# only if numbers
					$alarm_annotation =~ s/\s+//;
				} else {
					# not just numbers, short it down to max 10 chars
					$alarm_annotation = substr($alarm_annotation, 0, 10);
				}

                                # get ap-name
                                my $wmac = (split(',', $alarm->{'alarmsDTO'}->{'deviceName'}))[1];
                                next unless($wmac);
                                
				if(floor(str2time($alarm_timestamp)) > floor(str2time($alarm->{'alarmsDTO'}->{'lastUpdatedAt'}))){
					# only if annotation was created after alarm was updated
					# lets update DB
					debug_log("update alarm: $wmac, $alarm_annotation");
					$aplol->update_alarm($wmac, $alarm_annotation);
				}
                        }
                }
	}
}

# We only want 1 instance of this script running
# Check if already running -- if so, abort.
unless (flock(DATA, LOCK_EX|LOCK_NB)) {
	die("$0 is already running. Exiting.");
}

# connect
$aplol->connect();

# uptime
update_uptime();

# alarms
update_alarms();


$aplol->disconnect();


__DATA__
Do not remove. Makes sure flock() code above works as it should.
