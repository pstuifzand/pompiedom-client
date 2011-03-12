package Pompiedom::Network::Pompiedom;
use strict;
use warnings;
use 5.10.0;
use LWP::Simple qw/get/;
use LWP::UserAgent;
use Data::Dumper;

sub new {
    my ($klass, $messages, $settings) = @_;

    my $self = bless {
        settings   => $settings,
        last_check => {},
        messages   => $messages,
    }, $klass;

    return $self;
}

sub get_messages {
    my ($self) = @_;
    say 'get_messages';

    for my $url (@{$self->{settings}{urls}}) {
        say $url;
        my $lasttime = $self->{last_check}{$url};
        my $fetchurl = $url . "?lasttime=$lasttime";
        print "Getting message: $fetchurl\n";
        my $body = get($fetchurl);

        my $last_timestamp = 0;
        if ($body) {
            for my $line (split/\r\n/, $body) {
                my ($timestamp, $username, $message) = split/:/, $line, 3;
                print ".";

                $self->{messages}->insert_message({ id => join(':', $username, $timestamp), username => $username, timestamp => $timestamp, message => $message });

                if ($timestamp > $last_timestamp) {
                    $last_timestamp = $timestamp;
                }
            }
            $self->{last_check}{$url} = $last_timestamp;
        }
        print "\n";
        print Dumper($self->{last_check});
    }
}

sub post_message {
    my ($self, $url, $message, $user, $password) = @_;
    say 'post_message';

    my $ua = LWP::UserAgent->new;

    my $req = HTTP::Request->new(POST => $url);
    $ua->credentials($self->{settings}{post_domain}, $self->{settings}{post_realm}, $user, $password);
    $req->content_type('application/x-www-form-urlencoded');
    $req->content("message=$message");

    my $res = $ua->request($req);
    print $res->as_string;

    return;
}

1;
