package Pompiedom::Messages;
use 5.10.0;
use strict;
use warnings;

my @global_messages;
my %uniques;

sub new {
    my ($klass) = @_;
    return bless {}, $klass;
}

sub insert_message {
    my ($self, $message) = @_;

    if (!defined($uniques{$message->{id}})) {
        push @global_messages, $message;
        $uniques{$message->{id}} = 1;
    }

    return;
}

sub add_network {
    my ($self, $network) = @_;
    push @{$self->{networks}}, $network;
    return;
}

sub update {
    my ($self, $simplelist) = @_;
    say 'Update called';

    for my $network (@{$self->{networks}}) {
        $network->get_messages($self);
    }

    @global_messages = sort {$b->{timestamp} <=> $a->{timestamp}} @global_messages;
    @{$simplelist->{data}} = ();
    my $html = '<!DOCTYPE html><html><head><style>body{font-size:10pt;}</style></head><body>';
    for (@global_messages) {
        my $message = "<div style='margin:0;'>$_->{message}</div>\n<div style='font-size:9pt'>Posted by $_->{username}<br><a href='$_->{link}'>$_->{timestamp}</a></div><hr>";
        $html.=$message;
    }
    $html.="</body></html>";

    $simplelist->load_string($html, "text/html", "UTF-8", "http://peterstuifzand.com/");
#$simplelist->load_uri("http://stuifzand.eu");

    return;
}

1;
