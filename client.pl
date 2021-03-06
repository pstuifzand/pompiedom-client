#!/usr/bin/perl -w
use 5.10.0;
use lib 'lib';
use Gtk2 -init;

use YAML 'LoadFile';
use POE qw( Loop::Glib );
use POEx::HTTP::Server;
use Pompiedom::Client;
use Pompiedom::POE::RSS;
use POE::Component::Client::HTTP;
use POE::Component::Client::Keepalive;
use Pompiedom::Subscriptions;
use URI::Escape;

my $settings = LoadFile('settings.yml');

Pompiedom::Client->new();

POEx::HTTP::Server->spawn(
    inet => {
        BindPort => 5337,
        Reuse    => 1,
    },
    options => {
#        trace => 1,
    },
    #concurrency => 1,
    handlers => {
        '^/notify$', 'poe:subscriptions/notify',
    },
);

#my $pool = POE::Component::Client::Keepalive->new(
#    keep_alive    => 1, # seconds to keep connections alive
#    max_open      => 1, # max concurrent connections - total
#    max_per_host  => 1, # max concurrent connections - per host
#    timeout       => 1, # max time (seconds) to establish a new connection
#);

POE::Component::Client::HTTP->spawn(
    Alias             => 'ua',
#    Timeout           => 10,
#    ConnectionManager => $pool,
#    Protocol          => 'HTTP/0.9',
);

Pompiedom::POE::RSS->spawn(
    output_alias => 'pompiedom',
    %{$settings}
);

POE::Session->create(
    inline_states => {
        _start => sub {
            my ($kernel, $heap) = @_[KERNEL, HEAP];
            $kernel->alias_set('subscriptions');

            my $subs = Pompiedom::Subscriptions->new();
            $heap->{subscriptions} = $subs;

            $subs->load_subscriptions();

            for ($subs->subscriptions) {
                $kernel->yield('update_feed', $_);
            }
        },

        notify => sub {
            my ($heap, $req, $resp) = @_[HEAP,ARG0,ARG1];

            $resp->content_type('text/plain');
            $resp->content("rssCloud rocks!\r\n");
            $resp->respond;

            my ($url) = ($req->content) =~ m/url=(.+)/;
            say $url;
            $url = uri_unescape($url);

            $_[KERNEL]->yield('update_feed', $url);

            $resp->done;
        },

        _stop => sub {
            my ($kernel, $heap) = @_[KERNEL, HEAP];
            $kernel->alias_remove('subscriptions');
            $heap->{subscriptions}->save_subscriptions();
        },

        subscribe_cloud => sub {
            my ($kernel, $heap, $url, $cloud) = @_[KERNEL, HEAP, ARG0, ARG1];

            if (!$url) {
                say 'Empty url error in subscribe_cloud';
                return;
            }

            my $subs = $heap->{subscriptions};

            if ($subs->need_subscribe($url)) {
                print "Feed $url needs subscribe\n";
                $kernel->post('feed-reader' => 'subscribe_cloud' => $url => $cloud);
            }
            return;
        },

        update_feed => sub {
            my ($kernel, $heap, $url) = @_[KERNEL, HEAP, ARG0];
            if (!$url) {
                say 'Empty url error in update_feed';
                return;
            }
            my $subs = $heap->{subscriptions};

            if ($subs->need_update($url)) {
                print "Feed $url needs update\n";
                $kernel->post('feed-reader' => 'update_feed' => $url);
            }
            return;
        },

        feed_updated => sub {
            my ($kernel, $heap, $url) = @_[KERNEL, HEAP, ARG0];
            $heap->{subscriptions}->feed_updated($url);
        },

        feed_subscribed => sub {
            my ($kernel, $heap, $url) = @_[KERNEL, HEAP, ARG0];
            $heap->{subscriptions}->feed_subscribed($url);
        },
    },
);

$poe_kernel->run();

