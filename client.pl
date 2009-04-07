#!/usr/bin/perl -w
use strict;
use warnings;
 
use Data::Dumper;
use Gtk2 -init;
use Gtk2::GladeXML;
use Gtk2::SimpleList;
use LWP::Simple qw/get/;
use LWP::UserAgent;
use YAML qw/LoadFile DumpFile/;

my @global_messages;
my %uniques;
my %last_check;

my $settings;

sub save_messages {
    DumpFile('messages.yml', {
        messages => \@global_messages,
        last_check => \%last_check,
    });

    DumpFile('settings.yml', $settings);
    return;
}

sub load_messages {
    my $messages = eval { LoadFile('messages.yml') } || { messages => [], last_check => {} };

    @global_messages = @{$messages->{messages}};

    for (@global_messages) {
        $uniques{$_->{id}} = 1;
    }

    %last_check      = %{$messages->{last_check}};

    $settings = eval { LoadFile('settings.yml') } || {
        urls => [ 
            'http://peterstuifzand.nl/status/api.php' 
        ],
        update_speed => 120000,
        self_url => '',
        post_domain => '',
        post_realm => '',
        post_username => '',
        post_password => '',
    };

    return;
}

sub on_mainwindow_delete_event {
    save_messages();
    Gtk2->main_quit();
}

sub insert_message {
    my ($message) = @_;

    if (!defined($uniques{$message->{id}})) {
        push @global_messages, $message;
        $uniques{$message->{id}} = 1;
    }

    return;
}

sub update {
    my ($simplelist) = @_;

    for (@{$settings->{urls}}) {
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

sub post_message {
    my ($url, $message, $user, $password) = @_;

    my $ua = LWP::UserAgent->new;

    my $req = HTTP::Request->new(POST => $url);
    $ua->credentials($settings->{post_domain}, $settings->{post_realm}, $user, $password);
    $req->content_type('application/x-www-form-urlencoded');
    $req->content("message=$message");

    my $res = $ua->request($req);
    print $res->as_string;


    return;
}

my $gladexml = Gtk2::GladeXML->new('pompiedomclient.glade');
my $window = $gladexml->get_widget('mainwindow');
$window->set_size_request(300, 300);
$window->resize(300,600);

$gladexml->signal_autoconnect_from_package('main');

my $simplelist = Gtk2::SimpleList->new_from_treeview (
    $gladexml->get_widget ('treeview2'),
    'Message' => 'markup',
);

my $col = $simplelist->get_column(0);

for ($col->get_cell_renderers()) {
    $_->set_property('wrap-mode', 'word');
    $_->set_property('wrap-width', 260);
}

load_messages();

update($simplelist);
Glib::Timeout->add($settings->{update_speed}, sub { update($simplelist); return 1});

Gtk2->main();

sub on_send_message {
    my $self = shift;
    print "send message\n";

    my $entry = $gladexml->get_widget('entry1');
    my $message = $entry->get_text();

    post_message($settings->{self_url}, $message, $settings->{post_username}, $settings->{post_password});

    $entry->set_text('');

    return;
}
