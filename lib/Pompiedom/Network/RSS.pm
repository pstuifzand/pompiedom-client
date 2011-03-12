package Pompiedom::Network::RSS;
use 5.10.0;
use strict;
use warnings;

use Data::Dumper;
use HTML::Entities;
use XML::Feed;

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

    for my $url (@{$self->{settings}{urls}}) {
        say $url;
        my $uri = URI->new($url);
        eval {
            my $res = URI::Fetch->fetch($uri) or die URI::Fetch->errstr;
            my $feed_xml = $res->content;
            $feed_xml =~ s{<callbacktest:randomColor>azure</callbacktest:randomColor>}{};
            my $feed = XML::Feed->parse(\$feed_xml);

            for my $entry ($feed->entries) {
                $self->{messages}->insert_message({
                    id        => $entry->id,
                    username  => 'pstuifzand',
                    timestamp => $entry->issued,
                    message   => $entry->content->body,
                    link      => $entry->link,
                });
            }
        };
        if ($@) {
            print $@;
        }
    }
}

sub post_message {
    my ($self, $url, $message, $user, $password) = @_;
    my $ua = LWP::UserAgent->new;
    my $req = HTTP::Request->new(POST => $url);
    $ua->credentials($self->{settings}{post_domain}, $self->{settings}{post_realm}, $user, $password);
    $req->content_type('application/x-www-form-urlencoded');
    $req->content("text=$message");
    my $res = $ua->request($req);
    return;
}

1;
