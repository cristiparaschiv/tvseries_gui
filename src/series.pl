#!/usr/bin/perl

use strict;
use warnings;

use Data::Dumper;
use JSON;
use LWP::UserAgent;
use Time::Piece;
use Getopt::Long;

use threads;
use threads::shared;

use utf8;

require 'TraktTV.pm';

use Gtk3 '-init';
use Glib 'TRUE', 'FALSE';
use Gtk3::WebKit;

use constant COLUMN_DAY			=> 0;
use constant COLUMN_SHOW		=> 1;
use constant COLUMN_SEASON		=> 2;
use constant COLUMN_EPISODE 	=> 3;
use constant COLUMN_TITLE		=> 4;

use constant COLUMN_ACTIVE		=> 0;
use constant COLUMN_SUB_SHOW	=> 1;

# GLOBAL VARS
my $length = '7';
GetOptions (
	"days:i" => \$length
);
my @out_data = ();
our $window;
my $spinner;
my $tv;
my $sub_tv;
my $entry_shows;
my $search_entry;
our $images;

# MAIN APPLICATION

threads->create(sub {
	my $tid = threads->self->tid;
	print "Starting thread $tid\n";
	if (&check_shows_update()) {
		my $trakt = TraktTV->new();
		$trakt->get_shows();
		$entry_shows = &load_shows();
	} else {
		$entry_shows = &load_shows();
	}
	print "Ending thread $tid\n";
});

my $settings = Gtk3::Settings->get_default;
$settings->set('gtk-application-prefer-dark-theme', TRUE);

&render_window();
Gtk3->main();

# SUBS
sub load_shows {
	my $filename = "shows.json";
	open my $fh, "<", $filename;
	my $enc = <$fh>;
	close $fh;
	print "called load shows\n";
	return decode_json $enc;
}

sub check_shows_update {
	my $filename = 'shows.json';
	if (! -e $filename) {
		return 1;
	}
	open my $fh, "<", $filename;
	my $shows = <$fh>;
	close $fh;

	my $data = decode_json $shows;
	my $date = $data->{created};
	if (time > ($date + 2592000)) {
		print "Updating list of shows\n";
		return 1;
	} else {
		print "List of shows is up to date\n";
		return 0;
	}
}

sub render_window {
	$window = Gtk3::Window->new('toplevel');
	$window->set_title('TV Shows Notifier');
	$window->signal_connect(destroy => sub { Gtk3->main_quit; });
	$window->set_border_width(8);
	$window->set_default_size(600, 450);

	my $hb = Gtk3::HeaderBar->new;
	$hb->set_show_close_button(TRUE);
	$hb->set_title('TV Shows Notifier');
	$window->set_titlebar($hb);

	my $hbox = Gtk3::Box->new('horizontal', 5);
	my $but = Gtk3::Button->new_from_icon_name('edit-find-symbolic', 1);
	$but->signal_connect('clicked' => \&find, TRUE);
	$hbox->add($but);

	my $menu = Gtk3::Menu->new();
	my $mitem = Gtk3::MenuItem->new_with_label("Manage Subscriptions");
	$mitem->signal_connect('activate' => \&manage, TRUE);
	$menu->append($mitem);
	my $mb = Gtk3::MenuButton->new();
	my $img = Gtk3::Image->new_from_icon_name('open-menu-symbolic', 'button');
	$mitem->show;
	$mb->set_popup($menu);
	$hbox->pack_start($mb, TRUE, TRUE, 0);
	$mb->add($img);
	$mb->set_halign('end');

	$hb->pack_start($hbox);
	&add_widgets;
	$window->show_all;
}

sub get_subs {
	my $json;
	my $filename = 'subscriptions.json';
	if (-e $filename) {
		open my $fh, "<", $filename;
		$json = <$fh>;
		close $fh;
		return decode_json($json);
	} else {
		return {};
	}
}

### MANAGE SUBSCRIPTIONS ###

sub manage {
	my $sub_win = Gtk3::Window->new;
	$sub_win->set_title('Manage Subscriptions');
	$sub_win->set_border_width(8);
	$sub_win->set_default_size(350, 400);

	my $hb = Gtk3::HeaderBar->new;
	$hb->set_show_close_button(FALSE);
	$hb->set_title('Manage Subscriptions');
	$sub_win->set_titlebar($hb);

	my $box = Gtk3::Box->new('vertical', 5);

	my $sw = Gtk3::ScrolledWindow->new(undef, undef);
	$sw->set_shadow_type('etched-in');
	$sw->set_policy('never', 'automatic');
	$box->pack_start($sw, TRUE, TRUE, 5);

	my $sub_data = &get_subs();

	my @sub_data;
	foreach my $show (keys %$sub_data) {
		push @sub_data, {
			show => $show,
			active => $sub_data->{$show}->{active}
		};
	}

	my $model = set_sub_model(\@sub_data);

	$sub_tv = Gtk3::TreeView->new($model);
	$sub_tv->set_rules_hint(TRUE);
	$sub_tv->signal_connect(button_press_event => sub { &show_sub_menu(@_); });
	$sw->add($sub_tv);

	my $search_box = Gtk3::Box->new('horizontal', 5);

	$search_entry = Gtk3::Entry->new();
	$search_box->pack_start($search_entry, TRUE, TRUE, 0);
	
	my $completion = Gtk3::EntryCompletion->new();
	$search_entry->set_completion($completion);
	$entry_shows = &load_shows();
	my $completion_model = create_completion_model($entry_shows);
	$completion->set_model($completion_model);
	$completion->set_text_column(0);

	my $add_button = Gtk3::Button->new_from_stock('Add');
	$add_button->signal_connect('clicked' => \&add_sub, TRUE);
	$search_box->pack_start($add_button, FALSE, FALSE, 0);

	$box->pack_start($search_box, FALSE, FALSE, 5);

	my $close_but = Gtk3::Button->new_from_stock('Apply');
	$close_but->signal_connect('clicked' => sub {
		$sub_win->close;
	}, TRUE);

	$box->pack_start($close_but, FALSE, FALSE, 0);

	$sub_win->add($box);

	&add_sub_columns($sub_tv);

	$sub_win->set_transient_for($window);
	$sub_win->set_modal(TRUE);
	$sub_win->show_all;
}

sub add_sub {
	my $text = $search_entry->get_text();
	#print "$text\n";

	my $model = $sub_tv->get_model();
	my $iter = $model->append;
	$model->set(
		$iter, COLUMN_ACTIVE, 1, COLUMN_SUB_SHOW, $text 
	);

	my $subs = &get_subs();
	$subs->{$text} = {
		active => 1
	};
	&save_subscriptions($subs);
	$search_entry->set_text('');
}

sub create_completion_model {
	my $shows = shift;
	
	my $data = $shows->{shows};
	my $list = Gtk3::ListStore->new('Glib::String');
	
	foreach my $show (@$data) {
		my $iter = $list->append;
		$list->set($iter, 0,  $show);
	}
	
	return $list;
}

sub save_subscriptions {
	my $data = shift;

	my $json = encode_json($data);

	my $filename = "subscriptions.json";
	open my $fh, ">", $filename;
	print $fh $json;
	close $fh;
}

sub show_menu {
	my $tv = shift;
	my $event = shift;

	my $type = $event->type;
	my $button = $event->button;
	my $sel = $tv->get_selection;
	my ($model, $iter) = $sel->get_selected;
	if ($type eq 'button-press' and $button == 3 and defined $model) {
		&build_context($tv, $event);
	}
}

sub show_sub_menu {
	my $sub_tv = shift;
	my $event = shift;

	my $type = $event->type;
	my $button = $event->button;
	if ($type eq 'button-press' and $button == 3) {
		&build_sub_context($sub_tv, $event);
	}
}

my ($show_menu, $show_selected);

sub build_context {
	my $tv = shift;
	my $event = shift;

	$show_selected = $tv->get_selection;

	$show_menu = Gtk3::Menu->new();
	my $item = Gtk3::MenuItem->new('Show Details');
	$show_menu->append($item);
	$item->show;
	$item->signal_connect(activate => sub {
		&show_details($tv, $event, $show_selected);
	});

	$item = Gtk3::MenuItem->new('Episode Details');
	$show_menu->append($item);
	$item->show;
	$item->signal_connect(activate => sub {
		&episode_details($tv, $event, $show_selected);
	});

	$show_menu->popup(undef, undef, undef, undef, $event->button, $event->time);
}

my ($sub_menu, $sub_selected);

sub build_sub_context {
	my $tv = shift;
	my $event = shift;

	$sub_selected = $tv->get_selection;

	$sub_menu = Gtk3::Menu->new();
	my $item = Gtk3::MenuItem->new('Unsuscribe');
	$sub_menu->append($item);
	$item->show;
	$item->signal_connect(activate => sub {
		&remove_sub($tv, $event, $sub_selected);
	});
	$sub_menu->popup(undef, undef, undef, undef, $event->button, $event->time);
}

sub remove_sub {
	my $tv = shift;
	my $event = shift;
	my $selected = shift;

	my ($model, $iter) = $selected->get_selected;
	my $value = $model->get_value($iter, 1);

	$model->remove($iter);
	my $subs = &get_subs();
	delete $subs->{$value};
	&save_subscriptions($subs);
}

######################################################
### EPISODE DETAILS ACTION SUBROUTINE              ###
###                                                ###
### Draws the episode details window and calls the ###
### methods from TraktTv module.                   ###
######################################################

sub episode_details {
	my $tv = shift;
	my $event = shift;
	my $selected = shift;
	
	my ($model, $iter) = $selected->get_selected;
	my $show = $model->get_value($iter, 1);
	my $season = $model->get_value($iter, 2);
	my $episode = $model->get_value($iter, 3);
	my $title = $model->get_value($iter, 4);
	
	my $opts = {
		show => $show,
		season => $season,
		episode => $episode,
		title => $title
	};
	
	&draw_episode_details_window($opts);
	&get_episode_details($opts);
}

###############################################################################################
### GLOBAL VARIABLES FOR draw_episode_details_window                                        ###
my ($stack_window, $e_spinner, $spinner_box, $stack_switcher, $container, $details_box, $stack);
my ($banner_box, $banner);
my ($ep_box, $ep_show_label, $title_label, $ep_overview_label, $first_aired_label);
my ($sh_box, $sh_show_label, $sh_overview_label, $network_label);
################################################################################################

sub draw_episode_details_window {
	my $opts = shift;

	$container = Gtk3::Box->new('vertical', 5);
	$spinner_box = Gtk3::Box->new('horizontal', 5);
	$details_box = Gtk3::Box->new('vertical', 5);
	
	$e_spinner = Gtk3::Spinner->new;
	$e_spinner->start;
	$spinner_box->pack_start($e_spinner, TRUE, TRUE, 0);
	
	
	$stack_switcher = Gtk3::StackSwitcher->new;
	$stack_switcher->set_halign('center');
	$stack = Gtk3::Stack->new;
	$stack->set_transition_type('slide-left-right');
	$stack->set_transition_duration(1000);
	
	my $ep_box = Gtk3::Box->new('vertical', 5);
	my $sh_box = Gtk3::Box->new('vertical', 5);
	
	
	$banner = Gtk3::Image->new();
	$ep_box = Gtk3::Box->new('vertical', 5);
	$sh_box = Gtk3::Box->new('vertical', 5);
	
	$ep_show_label = Gtk3::Label->new();
	$title_label = Gtk3::Label->new();
	$ep_overview_label = Gtk3::Label->new();
	$first_aired_label = Gtk3::Label->new();
	$sh_show_label = Gtk3::Label->new();
	$sh_overview_label = Gtk3::Label->new();
	$network_label = Gtk3::Label->new();
	$ep_overview_label->set_size_request(400, -1);
	$ep_overview_label->set_line_wrap(TRUE);
	$ep_overview_label->set_max_width_chars(40);
	$ep_overview_label->set_justify('center');
	$sh_overview_label->set_size_request(400, -1);
	$sh_overview_label->set_line_wrap(TRUE);
	$sh_overview_label->set_max_width_chars(40);
	$sh_overview_label->set_justify('center');
	
	$ep_box->pack_start($ep_show_label, FALSE, FALSE, 3);
	$ep_box->pack_start($title_label, FALSE, FALSE, 3);
	$ep_box->pack_start($ep_overview_label, FALSE, FALSE, 3);
	$ep_box->pack_start($first_aired_label, FALSE, FALSE, 3);
	$sh_box->pack_start($sh_show_label, FALSE, FALSE, 3);
	$sh_box->pack_start($sh_overview_label, FALSE, FALSE, 3);
	$sh_box->pack_start($network_label, FALSE, FALSE, 3);
	
	$stack->add_titled($ep_box, 'episode', 'Episode Details');
	$stack->add_titled($sh_box, 'show', 'Show Details');
	
	$stack_switcher->set_stack($stack);
	
	$details_box->pack_start($banner, FALSE, FALSE, 2);
	$details_box->pack_start($stack_switcher, FALSE, FALSE, 2);
	$details_box->pack_start($stack, FALSE, FALSE, 2);
	
	$stack_window = Gtk3::Window->new();
	$stack_window->signal_connect(destroy => sub { $stack_window->close(); });
	$stack_window->set_title("$opts->{title} - $opts->{show}");
	$stack_window->set_border_width(10);
	$stack_window->set_default_size(500, 250);
	
	$container->pack_start($spinner_box, TRUE, TRUE, 0);
	$container->pack_start($details_box, TRUE, TRUE, 0);
	$stack_window->add($container);
	
	$stack_window->show_all;
	$spinner_box->show();
	$details_box->hide();
}

sub get_episode_details {
	my $opts = shift;
	
	my $data;
	
	$opts->{show} =~ s/ /-/g;
	
	threads->create(sub {
		my $trakt = TraktTV->new();
		my $episode_details = $trakt->get_episode_details($opts);
		my $images =  $trakt->get_show_images($opts);
		my $show_details =  $trakt->get_show_details($opts);
		$data->{episode} = $episode_details;
		$data->{images} = $images;
		$data->{show} = $show_details;
		
		&update_episode_window($data);
	});
}

sub update_episode_window {
	my $data = shift;
	
	my $images = $data->{images};
	my $episode_details = $data->{episode};
	my $show_details = $data->{show};
	
	my $overview = $episode_details->{overview};
	my $first_aired = $episode_details->{first_aired};

	my $show_overview = $show_details->{overview};
	my $show_network = $show_details->{network};
	my $show_country = $show_details->{country};
	my $show_homepage = $show_details->{homepage};
	my $show_status = $show_details->{status};
	my $show_first_aired = $show_details->{first_aired};
	my $title = $episode_details->{title};
	
	my $command = "wget -O /tmp/$$.jpg $images->{banner}";
	system ($command);
	
	$banner->set_from_file("/tmp/$$.jpg");
	my $text = "<span style=\"oblique\" weight=\"bold\">$show_details->{title}</span>";
	$ep_show_label->set_markup($text);
	$title_label->set_text($title);
	$ep_overview_label->set_text($overview);
	$first_aired_label->set_text($first_aired);
	
	$sh_show_label->set_markup($text);
	$sh_overview_label->set_text($show_overview);
	$network_label->set_text("Network: " . $show_network);
	
	$spinner_box->hide();
	$details_box->show();
}

my $details_window;


sub show_details {
	my $tv = shift;
	my $event = shift;
	my $selected = shift;

	$details_window = Gtk3::Window->new();
	$details_window->set_default_size(800, 600);
	$details_window->signal_connect(destroy => sub { $details_window->close; });

	my ($model, $iter) = $selected->get_selected;
	my $show = $model->get_value($iter, 1);
	my $season = $model->get_value($iter, 2);
	my $episode = $model->get_value($iter, 3);
	my $title = $model->get_value($iter, 4);


	my $view = Gtk3::WebKit::WebView->new();
	my $url = "https://trakt.tv/shows/$show/seasons/$season/episodes/$episode";
	$url =~ s/ /-/g;
	$view->load_uri($url);

	my $sw = Gtk3::ScrolledWindow->new();
	$sw->add($view);

	$details_window->set_title("$show - Season $season / Episode $episode - $title");
	$details_window->add($sw);
	$details_window->show_all();
}

sub toggle {
	my ($cell, $path_str, $model) = @_;

	my $path = Gtk3::TreePath->new($path_str);
	my $iter = $model->get_iter($path);
	my $active = $model->get_value($iter, COLUMN_ACTIVE);
	my $show = $model->get_value($iter, COLUMN_SUB_SHOW);

	$active ^= 1;

	$model->set($iter, COLUMN_ACTIVE, $active);

	my $sub_data = &get_subs();
	$sub_data->{$show}->{active} = $active;
	&save_subscriptions($sub_data);
}

sub add_widgets {
	my $box = Gtk3::Box->new('vertical', 8);
	$box->set_homogeneous(FALSE);
	$window->add($box);

	my $spinner_vbox = Gtk3::Box->new("horizontal", 5);
	$spinner = Gtk3::Spinner->new;

	$spinner_vbox->pack_start($spinner, FALSE, FALSE, 0);
	$spinner_vbox->pack_start(
		Gtk3::Label->new(
			'Search the shows you are subscripted to'
		),
		FALSE, FALSE, 0
	);

	$box->pack_start($spinner_vbox, FALSE, FALSE, 0);
	
	my $sw = Gtk3::ScrolledWindow->new(undef, undef);
	$sw->set_shadow_type('etched-in');
	$sw->set_policy('never', 'automatic');
	$box->pack_start($sw, TRUE, TRUE, 5);

	my $model = set_model(\@out_data);

	$tv = Gtk3::TreeView->new($model);
	$tv->set_rules_hint(TRUE);
	$tv->set_search_column(COLUMN_SHOW);
	$tv->signal_connect(button_press_event => sub { &show_menu(@_); });
	$sw->add($tv);

	add_columns($tv);
}

sub set_model {
	my $data = shift;

	my $model = Gtk3::ListStore->new('Glib::String', 'Glib::String', 'Glib::Uint', 'Glib::String', 'Glib::String',);
	for my $item (@$data) {
		my $iter = $model->append();
		$model->set(
			$iter, COLUMN_DAY, $item->{day}, COLUMN_SHOW, $item->{show}, COLUMN_SEASON, $item->{season}, COLUMN_EPISODE, $item->{episode}, COLUMN_TITLE, $item->{title}
		);

	}
	
	return $model;
}

sub set_sub_model {
	my $data = shift;

	my $model = Gtk3::ListStore->new('Glib::Boolean', 'Glib::String',);
	for my $item (@$data) {
		my $iter = $model->append();
		$model->set(
			$iter, COLUMN_ACTIVE, $item->{active}, COLUMN_SUB_SHOW, $item->{show}
		);
	}

	return $model;
}

sub call2 {
	my $subscription = &get_subs();
	#print Dumper $subscription;
	my $trakt = new TraktTV($length, $subscription);
	my $data = $trakt->get_data();

	return $data;
}

sub find {
	my $data;

	threads->create(sub {
		my $tid = threads->self->tid;
		print "Starting thread $tid\n";
		$spinner->start;
		print "Ending thread $tid\n";
	});
	threads->create(sub {
		my $tid = threads->self->tid;
		print "Starting thread $tid\n";
		$data = &call2;
		$spinner->stop;
		print "Ending thread $tid\n";
		&update_list($data);
	});
}

sub update_list {
	my $data = shift;

	my $model = set_model($data);
	$tv->set_model($model);
}


sub add_sub_columns {
	my $tv = shift;
	my $model = $tv->get_model();

	my $renderer = Gtk3::CellRendererToggle->new;
	$renderer->signal_connect(toggled => \&toggle, $model);
	my $column = Gtk3::TreeViewColumn->new_with_attributes('Enabled', $renderer, active => COLUMN_ACTIVE);
	$column->set_sizing('fixed');
	$column->set_fixed_width(60);
	$tv->append_column($column);

	$renderer = Gtk3::CellRendererText->new;
	$column = Gtk3::TreeViewColumn->new_with_attributes('Show', $renderer, text => COLUMN_SUB_SHOW);
	$column->set_sort_column_id(COLUMN_SUB_SHOW);
	$tv->append_column($column);
}

sub add_columns {
	my $tv = shift;
	my $model = $tv->get_model();

	my $renderer = Gtk3::CellRendererText->new;
	my $column = Gtk3::TreeViewColumn->new_with_attributes('Day', $renderer, text => COLUMN_DAY);
	$column->set_sort_column_id(COLUMN_DAY);
	$tv->append_column($column);

	$renderer = Gtk3::CellRendererText->new;
	$column = Gtk3::TreeViewColumn->new_with_attributes('Show', $renderer, text => COLUMN_SHOW);
	$column->set_sort_column_id(COLUMN_SHOW);
	$tv->append_column($column);

	$renderer = Gtk3::CellRendererText->new;
	$column = Gtk3::TreeViewColumn->new_with_attributes('Season', $renderer, text => COLUMN_SEASON);
	$column->set_sort_column_id(COLUMN_SEASON);
	$tv->append_column($column);

	$renderer = Gtk3::CellRendererText->new;
	$column = Gtk3::TreeViewColumn->new_with_attributes('Episode', $renderer, text => COLUMN_EPISODE);
	$column->set_sort_column_id(COLUMN_EPISODE);
	$tv->append_column($column);

	$renderer = Gtk3::CellRendererText->new;
	$column = Gtk3::TreeViewColumn->new_with_attributes('Title', $renderer, text => COLUMN_TITLE);
	$column->set_sort_column_id(COLUMN_TITLE);
	$tv->append_column($column);
}


