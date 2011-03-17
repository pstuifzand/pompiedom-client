package XML::Feed::Format::RSS;
sub cloud {
    my ($self) = @_;
    return $self->{rss}->channel('cloud');
}

package Pompiedom::Network::RSS;
use 5.10.0;
use strict;
use warnings;

use YAML qw/LoadFile DumpFile/;
use Data::Dumper;
use HTML::Entities;
use XML::Feed;

sub new {
    my ($klass, $messages, $settings) = @_;

    my $self = bless {
        settings   => $settings,
        last_check => {},
        messages   => $messages,
        subscriptions => eval { LoadFile('subscriptions.yml') } || {},
    }, $klass;

    return $self;
}

sub save_subscriptions {
    my ($self) = @_;
    DumpFile('subscriptions.yml', $self->{subscriptions});
}

sub subscribe {
    my ($self, $url, $cloud) = @_;

    if (   $cloud->{domain} 
        && $cloud->{port} 
        && $cloud->{path} 
        && defined($cloud->{registerProcedure})
        && ($cloud->{protocol} eq 'http-post')) {

        my $sub = $self->{subscriptions}{$url->as_string};

        if ($sub->{last_time} < (time() - 60 * 60 * 24)) {
            $sub->{last_time} = time();
            $self->save_subscriptions();

            # re subscribe

            say "Resubscribing to $url";

            my $subscribe_uri = URI->new('http://'.$cloud->{domain}.':'.$cloud->{port}.$cloud->{path});
            my $ua = LWP::UserAgent->new();
            my $res = $ua->post($subscribe_uri->as_string, {
                    notifyProcedure => '',
                    port            => 5337,
                    path            => '/notify',
                    protocol        => 'http-post',
                    url1            => $url->as_string,
                });
            print $res->content . "\n";
        }
        else {
            say "Not long enough ago";
        }
    }
    else {
        say "Not a cloud feed";
    }
    return;
}

sub get_messages {
    my ($self, $url) = @_;

    my @urls;

    if ($url) {
        push @urls, $url;
    }
    else {
        @urls = @{$self->{settings}{urls}};
    }

    for my $url (@urls) {
        say $url;
        my $uri = URI->new($url);
        eval {
            my $res = URI::Fetch->fetch($uri) or die URI::Fetch->errstr;
            my $feed_xml = $res->content;
            $feed_xml =~ s{<callbacktest:randomColor>azure</callbacktest:randomColor>}{};
            my $feed = XML::Feed->parse(\$feed_xml);

            my $cloud = $feed->cloud;
            print Dumper($cloud);
            #        $self->subscribe($uri, $cloud);

            for my $entry ($feed->entries) {
                $self->{messages}->insert_message({
                    id        => $entry->id,
                    author    => scalar ($feed->author || $uri->host),
                    timestamp => $entry->issued,
                    message   => $entry->content->body,
                    link      => $entry->link,
                    title     => $entry->title,
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
