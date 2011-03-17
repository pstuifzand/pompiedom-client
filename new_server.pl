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
        [ 'Screen', min_level => 'debug', stderr => 1 ],
        [ 'File',   min_level => 'debug', filename => 'pompiedom.log' ],
    ],
);

$log->warning("Loading settings.yml\n");
my $settings = LoadFile('settings.yml');

$log->info("Spawning POEx::HTTP::Server ");
POEx::HTTP::Server->spawn(
    inet => {
        BindPort => 5337,
        Reuse    => 1,
    },
    handlers => {
        '^/notify$', 'poe:subscriptions/notify',
    },
);
$log->info("done\n");

$log->info("Spawning POE::Component::Client::HTTP ");
POE::Component::Client::HTTP->spawn(
    Alias => 'ua',
);
$log->info("done\n");

$log->info("Spawning Pompiedom::POE::RSS ");
Pompiedom::POE::RSS->spawn(
    output_alias => 'to_client',
    %{$settings}
);
$log->info("done\n");

$log->info("Spawning POE::Session(subscriptions) ");
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

            $log->info("[init_subscriptions]\n");
            $heap->{subscriptions}->load_subscriptions();

            for ($heap->{subscriptions}->subscriptions) {
                $log->info("Update feed " . Dumper($_));
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
$log->info("done\n");

$log->info("Spawning POE::Session(expected: to_client)\n");
POE::Session->create(
    heap => { alias => 'to_client' },

    inline_states => {
        _start => sub {
            my ($kernel, $heap) = @_[KERNEL,HEAP];
            $log->info("Starting POE::Session(".$heap->{alias}.")\n");

            $kernel->alias_set($heap->{alias});

            my $ctx = ZeroMQ::Context->new();

            $log->info("  Spawning POE::Wheel::ZeroMQ\n");
            $heap->{wheel} = POE::Wheel::ZeroMQ->new(
                SocketType => ZMQ_PUB,
                SocketBind => 'tcp://127.0.0.1:55559',
                Context    => $ctx,
            );
            $log->info("  Done\n");

            $heap->{ctx} = $ctx;

            $log->info(" Done\n");

        },

        _stop => sub {
            $_[HEAP]->{ctx}->term;
        },

        insert_message => sub {
            my ($kernel, $heap, $message) = @_[KERNEL, HEAP, ARG0];
            $log->info("   POE::Session(".$heap->{alias}.") sending message\n");
            $heap->{wheel}->send(encode_json($message));
            $log->info("   Done\n");
            return;
        },

        update => sub {
            my ($kernel, $heap) = @_[KERNEL, HEAP];
            # Nothing
            $log->info("POE::Session(".$heap->{alias}.") update\n");
            return;
        },
    },
);
$log->info("done\n");

POE::Kernel->run();

