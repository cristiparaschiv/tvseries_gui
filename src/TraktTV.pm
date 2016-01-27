package TraktTV;

use JSON;
use Data::Dumper;
use LWP::UserAgent;
use Time::Piece;

sub new {
	my $class = shift;
	my $length = shift // 7;
	my $subscriptions = shift;
	my $self = {
		api => "3d3a731171786c0f91b934923592ea87",
		ua => LWP::UserAgent->new,
		client_id => "151216db7d18bf7e6024552ce1548d795aba23f50fdd01a97c7fe6acf6f41ba2",
		length => $length,
		subscriptions => $subscriptions,
	};

	my $api = $self->{api};
	my $ua = $self->{ua};
	my $client_id = $self->{client_id};
	
	$ua->default_header("Content-Type" => "application/json");
	$ua->default_header("trakt-api-version" => "2");
	$ua->default_header("trakt-api-key" => $client_id);
	
	bless $self, $class;
	
	return $self;
}

sub get_episode_details {
	my $self = shift;
	my $opts = shift;
	my $ua = $self->{ua};

	my $url = "http://api-v2launch.trakt.tv/shows/" . $opts->{show} . "/seasons/" . $opts->{season} . "/episodes/" . $opts->{episode} . "?extended=full";

	my $response = $ua->get($url);
	my $data;
	if ($response->is_success) {
		$data = $response->decoded_content;
	} else {
		die $response->status_line;
	}
	my $json = decode_json($data);

	my $output = {
		overview => $json->{overview},
		first_aired => $json->{first_aired},
		imdb_id => $json->{ids}->{imdb},
		trakt_id => $json->{ids}->{trakt},
		title => $json->{title},
	};

	return $output;
}

sub get_show_details {
	my $self = shift;
	my $opts = shift;
	my $ua = $self->{ua};

	my $url = "http://api-v2launch.trakt.tv/shows/" . $opts->{show} . "?extended=full";
	
	my $response = $ua->get($url);
	my $data;
	if ($response->is_success) {
		$data = $response->decoded_content;
	} else {
		die $response->status_line;
	}
	my $json = decode_json($data);
	
	my $output = {
		title => $json->{title},
		year => $json->{year},
		overview => $json->{overview},
		first_aired => $json->{first_aired},
		network => $json->{network},
		country => $json->{country},
		homepage => $json->{hompage},
		status => $json->{status},
	};

	return $output;
}

sub get_show_images {
	my $self = shift;
	my $opts = shift;
	my $ua = $self->{ua};

	my $url = "http://api-v2launch.trakt.tv/shows/" . $opts->{show} . "?extended=images";
	my $data;
	my $response = $ua->get($url);
	if ($response->is_success) {
		$data = $response->decoded_content;
	} else {
		die $response->status_line;
	}
	my $json = decode_json($data);

	my $output = {
		fanart => $json->{images}->{fanart}->{full},
		poster => $json->{images}->{poster}->{full},
		logo => $json->{images}->{logo}->{full},
		banner => $json->{images}->{banner}->{full},
		thumb => $json->{images}->{thumb}->{full},
	};

	return $output;
}

sub uniq {
	my %seen;
	return grep { !$seen{$_}++ } @_;
}

sub get_shows {
	my $self = shift;

	my $ua = $self->{ua};

	my $date = localtime->strftime('%Y%m%d');
	my $response = $ua->get("http://api-v2launch.trakt.tv/calendars/all/shows/$date/30");
	my $data;
	if ($response->is_success) {
		$data = $response->decoded_content;
	} else {
		die $response->status_line;
	}

	my $json = decode_json($data);
	my $data = {
		'created' => time,
		'shows' => []
	};

	foreach my $show (@$json) {
		push @{$data->{shows}}, $show->{show}->{title};
	}
	my @uniq = uniq(@{$data->{shows}});
	$data->{shows} = \@uniq;
	my $data_json = encode_json($data);

	my $filename = 'shows.json';
	open my $fh, ">", $filename;
	print $fh $data_json;
	close $fh;
}

sub get_data {
	my $self = shift;
	my $ua = $self->{ua};
	
	my $subscription = $self->{subscriptions};
	my $data;
	my @out_data = ();

	my $date = localtime->strftime('%Y%m%d');
	my $length = $self->{length};
		
	my $response = $ua->get("http://api-v2launch.trakt.tv/calendars/shows/$date/$length?extended=images");

	if ($response->is_success) {
		$data =  $response->decoded_content;
	} else {
		die $response->status_line;
	}

	my $json = JSON->new;
	my $r = $json->decode($data);

	# Process response
	my $alert = {};
	my $message;
	my $alt = "";
	my ($season, $number, $title, $aired, $banner);
	
	#lowercase subscriptions
	my $input = {};
	foreach my $show (keys %$subscription) {
		$input->{lc($show)} = $subscription->{$show};
	}

	foreach my $day (sort keys %$r) {
		my $count = 0;
		$message .= "<h3>$day</h3>";
		$alt .= "$day\n----------------------\n";

		foreach my $show (@{$r->{$day}}) {
			my $key = lc($show->{show}->{title});
			if (exists $input->{$key} and $input->{$key}->{active} == 1) {
		#	print Dumper $show;
			    $count = 1;
			    $season = $show->{episode}->{season};
			    $number = $show->{episode}->{number};
			    $title = $show->{episode}->{title};
			    $aired = $show->{airs_at};
			    $banner = $show->{show}->{images}->{banner}->{full};

			    $message .= "&nbsp;&nbsp;<b>" . $show->{show}->{title} . "</b><br>";
			    if (defined $banner) {
			        $message .= "&nbsp;&nbsp;<img src=\"" . $banner . "\" width=\"50%\"><br>";
			    }
			    $message .= "&nbsp;&nbsp;&nbsp;&nbsp;Season $season / episode $number: $title<br>";
			    $message .= "&nbsp;&nbsp;&nbsp;&nbsp;Airing time: $aired<br>";
				$alt .= "    " . $show->{show}->{title} . "\n      Season $season / episode $number: $title\n\n";

				my $temp = {
					day => $day,
					show => $show->{show}->{title},
					season => $season,
					episode => $number,
					title => $title,
					banner => $banner,
				};
				push @out_data, $temp;

			}
		}
		if ($count == 0) {
			$message .= "&nbsp;&nbsp;-- no subscription for this date<br>";
			$alt .= "    -- nu subscription for this date\n";    
		}
	}
		#print $message;
		#print $alt;
		#print Dumper \@out_data;
#		open(my $fh, '>', "out_data.pl");
#		print $fh Dumper \@out_data;
#		close $fh;
		
		return \@out_data;
}

1;
