use strict;
use warnings;

use JSON;
use Data::Dumper;

our $subscription = {
	'revolution' => {},
	'the 100' => {},
	'the big bang theory' => {},
	'family guy' => {},
	'american dad' => {},
	'the simpsons' => {},
	'the walking dead' => {},
	'the blacklist' => {},
	'person of interest' => {},
	'grimm' => {},
	'helix' => {},
	'resurrection' => {},
	'under the dome' => {},
	'it\'s always sunny in philadelphia' => {},
	'silicon valley' => {},
	'halt and catch fire' => {},
	'the last ship' => {},
	'the strain' => {},
	'extant' => {},
	'z nation' => {},
	'forever (2014)' => {},
	'scorpion' => {},
	'american horror story' => {},
	'penny dreadful' => {},
    'the whispers' => {},
    'wayward pines' => {},
    'dark matter' => {},
    'humans' => {},
    'izombie' => {},
    'between' => {},
    'mr. robot' => {},
    'fear the walking dead' => {}
};

for my $show (keys %$subscription) {
	$subscription->{$show}->{active} = 1;
}

my $json = encode_json $subscription;
open my $fh, ">", "subscriptions.json";
print $fh $json;
close $json;
