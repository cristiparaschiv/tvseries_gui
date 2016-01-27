#!/usr/bin/perl

use strict;
use warnings;
use JSON;
use Getopt::Long;

use Data::Dumper;

require 'TraktTV.pm';

#LOAD SUBSCRIPTIONS FROM JSON
open my $fh, "<", 'subscriptions.json';
my $json = <$fh>;
close $fh;
my $subscription = decode_json($json);

my $length = '7';
GetOptions (
	"days:i" => \$length
);
my @out_data = ();

#FETCH DATA FROM TRAKTTV MODULE
my $trakt = new TraktTV($length, $subscription);
my $dd = $trakt->get_data();

#SAVE DATA TO FILE
open($fh, '>', "out_data.pl");
print $fh Dumper $dd;
close $fh;
