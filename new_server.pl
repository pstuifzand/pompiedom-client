#!/usr/bin/perl -w
use strict;
use warnings;

use 5.10.0;
use lib 'lib';

use Data::Dumper;

use ZeroMQ qw(:all);
use POE::Wheel::ZeroMQ;

use POE;

use YAML 'LoadFile';
use POEx::HTTP::Server;
use Pompiedom::POE::RSS;
use POE::Component::Client::HTTP;
use POE::Component::Client::Keepalive;
use Pompiedom::Subscriptions;
use URI::Escape;

use JSON;
use Log::Dispatch;

my $version_string = ZeroMQ::version();
print "Starting with ZMQ $version_string\n";

my $log = Log::Dispatch->new(
    outputs => [
        [ 'Screen', min_level => 'warning', stderr => 1 ],
        [ 'File',   min_level => 'debug', filename => 'pompiedom.log' ],
    ],
);

$log->warning("Loading settings.yml\n");
my $settings = LoadFile('settings.yml');

$log->debug("Spawning POEx::HTTP::Server ");
POEx::HTTP::Server->spawn(
    inet => {
        BindPort => 5337,
        Reuse    => 1,
    },
    handlers => {
        '^/notify$', 'poe:subscriptions/notify',
    },
);
$log->debug("done\n");

$log->debug("Spawning POE::Component::Client::HTTP ");
POE::Component::Client::HTTP->spawn(
    Alias => 'ua',
);
$log->debug("done\n");

$log->debug("Spawning Pompiedom::POE::RSS ");
Pompiedom::POE::RSS->spawn(
    output_alias => 'to_client',
    %{$settings}
);
$log->debug("done\n");

$log->debug("Spawning POE::Session(subscriptions) ");
POE::Session->create(
    inline_states => {
        _start => sub {
            my ($kernel, $heap) = @_[KERNEL, HEAP];
            $kernel->alias_set('subscriptions');

            my $subs = Pompiedom::Subscriptions->new();
            $heap->{subscriptions} = $subs;

            $kernel->delay('init_subscriptions', 3);
        },

        init_subscriptions => sub {
            my ($kernel, $heap) = @_[KERNEL, HEAP];

            $log->debug("[init_subscriptions]\n");
            $heap->{subscriptions}->load_subscriptions();

            for ($heap->{subscriptions}->subscriptions) {
                $log->debug("Update feed " . Dumper($_));
                $kernel->yield('update_feed', $_, { force => 1 });
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

            $_[KERNEL]->yield('update_feed', $url, { force => 1 });

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
            my ($kernel, $heap, $url, $options) = @_[KERNEL, HEAP, ARG0, ARG1];
            $options ||= {};
            if (!$url) {
                say 'Empty url error in update_feed';
                return;
            }
            my $subs = $heap->{subscriptions};

            if ($options->{force} || $subs->need_update($url)) {
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
$log->debug("done\n");

$log->debug("Spawning POE::Session(expected: to_client)\n");
POE::Session->create(
    heap => { alias => 'to_client' },

    inline_states => {
        _start => sub {
            my ($kernel, $heap) = @_[KERNEL,HEAP];
            $log->debug("Starting POE::Session(".$heap->{alias}.")\n");

            $kernel->alias_set($heap->{alias});

            my $ctx = ZeroMQ::Context->new();

            $log->debug("  Spawning POE::Wheel::ZeroMQ\n");
            $heap->{wheel} = POE::Wheel::ZeroMQ->new(
                SocketType => ZMQ_PUB,
                SocketBind => 'tcp://127.0.0.1:55559',
                Context    => $ctx,
            );
            $log->debug("  Done\n");

            $heap->{ctx} = $ctx;

            $log->debug(" Done\n");

        },

        _stop => sub {
            $_[HEAP]->{ctx}->term;
        },

        insert_message => sub {
            my ($kernel, $heap, $message) = @_[KERNEL, HEAP, ARG0];
            $heap->{wheel}->send(encode_json($message));
            return;
        },

        update => sub {
            my ($kernel, $heap) = @_[KERNEL, HEAP];
            # Nothing
            $log->debug("POE::Session(".$heap->{alias}.") update\n");
            return;
        },
    },
);
$log->debug("done\n");

POE::Kernel->run();

