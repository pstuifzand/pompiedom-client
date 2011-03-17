#!/usr/bin/perl -w
use strict;
use warnings;
use 5.10.0;
use lib 'lib';

use ZeroMQ qw(:all);

use Gtk2 -init;

use POE qw( Loop::Glib );
use POE::Wheel::ZeroMQ;
use Pompiedom::Client;

use Log::Dispatch;
use JSON;
use Data::Dumper;
use DateTime::Format::RFC3339;

my $log = Log::Dispatch->new(
    outputs => [
        [ 'Screen', min_level => 'debug', stderr => 1 ],
        [ 'File',   min_level => 'debug', filename => 'pompiedom-client.log' ],
    ],
);

Pompiedom::Client->new();

$log->info("Spawning POE::Session(from_server)\n");
POE::Session->create(
    inline_states => {
        _start => sub {
            my ($kernel, $heap) = @_[KERNEL,HEAP];
            $kernel->alias_set('from_server');

            my $ctx = ZeroMQ::Context->new();

            $log->info(" Spawning POE::Wheel::ZeroMQ\n");
            $heap->{wheel} = POE::Wheel::ZeroMQ->new(
                SocketType    => ZMQ_SUB,
                SocketConnect => 'tcp://127.0.0.1:55559',
                InputEvent    => 'on_data_recieved',
                ErrorEvent    => 'on_error',
                Subscribe     => '',
                Context       => $ctx,
            );
            $heap->{ctx} = $ctx;
            $log->info(" Done\n");
        },

        _stop => sub {
            my ($kernel, $heap) = @_[KERNEL,HEAP];
            $heap->{ctx}->term;
        },

        on_data_recieved => sub {
            my ($kernel, $heap, $messages) = @_[KERNEL, HEAP, ARG0];
            $log->info("on_data_recieved\n");

            my $f = DateTime::Format::RFC3339->new();

            for my $msg (@$messages) {
                $log->info(localtime()." message recieved\n");
                my $message = decode_json($msg->data);
                $message->{timestamp} = $f->parse_datetime($message->{timestamp});
                $kernel->post('pompiedom', 'insert_message', $message);
            }
            $kernel->post('pompiedom', 'update');
            $log->info(localtime()." updates complete\n");
        },
        ping => sub {
            my ($kernel, $heap) = @_[KERNEL,HEAP];
            $kernel->delay('ping', 2);
        },
    },
);
$log->info("Done\n");

POE::Kernel->run();
