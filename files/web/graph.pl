#!/usr/bin/perl
use warnings;
use strict;
use CGI;

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

# return 200 OK
sub header{
	return CGI::header(
		-type => 'text/html',
		-status => '200',
		-charset => 'utf-8'
	);
}

# print the page
sub print_page{
	my ($title, $yaxis, $json_url) = @_;

	print header();
	print <<LOLZ;
<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Strict//EN" "http://www.w3.org/TR/xhtml1/DTD/xhtml1-strict.dtd">
<html xmlns="http://www.w3.org/1999/xhtml" xml:lang="en">
	<head>
		<title>$title</title>
		<script type='text/javascript' src='/js/jquery.js'></script>
		<script type='text/javascript' src='/js/highstock.js'></script>
		<script type='text/javascript' src='/js/highstock-exporting.js'></script>

		<script>
			\$(function() {
				var seriesOptions = [],
				yAxisOptions = [],
				colors = Highcharts.getOptions().colors;

				\$.getJSON('$json_url', function(json){
					\$('#container').highcharts('StockChart', {
						chart: {
				                	zoomType: 'x',
			        	        	type: 'line',
			                		animation: false,
			                		//backgroundColor:'transparent'
					    	},

					    	title: {
							text: '$title'
					    	},

					    	navigator: {
					                series: {
				                    		type: 'line'
			        	        	}
				            	},

					    	xAxis: {
			              			ordinal: false,
			              			mode: 'time',
			            	    	},

					    	yAxis: {
				                        title: {
			        				text: '$yaxis'
			                        	},
				
					    		labels: {
								formatter: function() {
									return this.value;
								}
					    		},

					    		plotLines: [{
					    			value: 0,
					    			width: 1,
					    			color: 'silver'
					    		}],
						},

						legend: {
			              			enabled: true,
							layout: 'vertical',
							align: 'right',
							verticalAlign: 'top',
			              			y: 100
						},
					    
						plotOptions: {
							series: {
								animation: false,
					    		}
						},
					    
						tooltip: {
							pointFormat: '<span style="color:{series.color}">{series.name}</span>: <b>{point.y}</b><br/>',
							valueDecimals: 0
						},
					    
						series: json
					});
				});
			});
		</script>
	</head>
	<body>
		<div id="container" style="height: 800px; min-width: 310px"></div>
	</body>
</html>
LOLZ
}

my $cgi = CGI->new();
my $graph = $cgi->param('g');

if($graph){
	if($graph =~ m/^total$/){
		print_page("Total number of APs", "Number of APs", "/aplol.pl?p=graph-total");
	} elsif($graph =~ m/^vd$/){
		print_page("Total number of APs", "Number of APs", "/aplol.pl?p=graph-vd");
	} elsif($graph =~ m/^wlc$/){
		print_page("Total number of APs", "Number of APs", "/aplol.pl?p=graph-wlc");
	} else {
		# not a valid graph
		print CGI::header(
			-type => 'text/plain',
			-status => '404',
			-charset => 'utf-8'
		);
		exit 0;
	}
} else {
	print CGI::header(
		-type => 'text/plain',
		-status => '404',
		-charset => 'utf-8'
	);
	exit 0;
}

exit 0;
