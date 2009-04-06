#!/usr/bin/perl -w
use strict;
use warnings;
 
use Data::Dumper;
use Gtk2 -init;
use Gtk2::GladeXML;
use Gtk2::SimpleList;
use LWP::Simple qw/get/;

sub on_mainwindow_delete_event {
    Gtk2->main_quit();
}

sub on_send_message {
    my $self = shift;
    print "send message\n";
    return;
}

my @global_messages;
my %uniques;

sub insert_message {
    my ($message) = @_;

    if (!defined($uniques{$message->{id}})) {
        push @global_messages, $message;
        $uniques{$message->{id}} = 1;
    }

    return;
}

my @urls = ('http://peterstuifzand.nl/status/api.php');
my %last_check;

sub update {
    my ($simplelist) = @_;

    for (@urls) {
        get_messages($_, $last_check{$_});
    }

    @global_messages = sort {$b->{timestamp} <=> $a->{timestamp}} @global_messages;
    @{$simplelist->{data}} = ();
    for (@global_messages) {
        my $message = "$_->{message}\n<span font_size='small'>Posted by $_->{username} on $_->{timestamp}</span>";
        push @{$simplelist->{data}}, $message;
    }

    return;
}

sub get_messages {
    my ($url, $lasttime) = @_;

    my $fetchurl = $url . "?lasttime=$lasttime";
    print "Getting message: $fetchurl\n";
    my $body = get($fetchurl);

    my $last_timestamp=0;
    if ($body) {
        for my $line (split/\r\n/, $body) {
            my ($timestamp, $username, $message) = split/:/, $line, 3;
            print ".";

            insert_message({ id => join(':', $username, $timestamp), username => $username, timestamp => $timestamp, message => $message });

            if ($timestamp > $last_timestamp) {
                $last_timestamp = $timestamp;
            }
        }
        $last_check{$url} = $last_timestamp;
    }
    print "\n";
    print Dumper(\%last_check);

    return;
}

my $gladexml = Gtk2::GladeXML->new('pompiedomclient.glade');
$gladexml->signal_autoconnect_from_package('main');

my $simplelist = Gtk2::SimpleList->new_from_treeview (
    $gladexml->get_widget ('treeview2'),
    'Message' => 'markup',
);

my $col = $simplelist->get_column(0);

for ($col->get_cell_renderers()) {
    $_->set_property('wrap-mode', 'word');
    $_->set_property('wrap-width', 500);
}

update($simplelist);
Glib::Timeout->add(120000, sub { update($simplelist); return 1});

Gtk2->main();

