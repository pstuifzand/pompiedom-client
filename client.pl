#!/usr/bin/perl -w

use strict;
use warnings;
use lib 'lib';
 
use Data::Dumper;
use Gtk2 -init;
use Gtk2::GladeXML;
use Gtk2::SimpleList;
use Gtk2::WebKit;
use YAML qw/LoadFile DumpFile/;

use Pompiedom::Messages;
use Pompiedom::Network::Pompiedom;
use Pompiedom::Network::RSS;

my $gladexml = Gtk2::GladeXML->new('pompiedomclient.glade');
my $window = $gladexml->get_widget('mainwindow');
$window->set_size_request(300, 300);
$window->resize(300,600);

$gladexml->signal_autoconnect_from_package('main');

my $scrolled = $gladexml->get_widget('scrolledwindow2');
my $view = Gtk2::WebKit::WebView->new();
$view->show_all;
$scrolled->add($view);

my $messages = Pompiedom::Messages->new();

my $settings = LoadFile('settings.yml'); 
my $rss = Pompiedom::Network::RSS->new($messages, $settings);
$messages->add_network($rss);
$messages->update($view);

Glib::Timeout->add($settings->{update_speed}, sub { $messages->update($view); return 1});

Gtk2->main();

sub on_mainwindow_delete_event {
    Gtk2->main_quit();
}

sub on_send_message {
    my $self = shift;
    my $entry = $gladexml->get_widget('entry1');
    my $message = $entry->get_text();
    $rss->post_message(
        $settings->{self_url}, $message, 
        $settings->{post_username}, $settings->{post_password}
    );
    $entry->set_text('');
    return;
}

