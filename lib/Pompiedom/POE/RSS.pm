package Pompiedom::POE::RSS;
use strict;
use warnings;
use LWP::UserAgent;
use XML::Feed;
use HTTP::Request;
use POE;
use HTTP::Request::Common;
use Data::Dumper;
use MIME::Base64;
use URI::Escape;
use DateTime::Format::RFC3339;

sub spawn {
    my ($package, %options) = @_;
    my $self = $package->new(%options);
    my $session = $self->build_session();
    return $self->{alias};
}

sub new {
    my ($package, %options) = @_;
    my $self = bless { options => \%options }, $package;
    return $self;
}

sub build_session {
    my ($self) = @_;
    my $package = __PACKAGE__;

    return POE::Session->create(
        args => [ $self->{options}{output_alias} ],
        inline_states => {

            _start => sub {
                my ($kernel, $heap, $arg) = @_[KERNEL, HEAP, ARG0];
                $kernel->alias_set('feed-reader');
                $heap->{output_alias} = $arg;
            },
            _stop => sub {
                print "feed-reader stopped\n";
            },
            shutdown => sub {
                $_[KERNEL]->alias_remove('feed-reader');
            },

            update_feed => sub {
                my ($kernel, $heap, $url) = @_[KERNEL,HEAP,ARG0];
                print "update_feed URL: " . $url . "\n";
                my $req = HTTP::Request->new(GET => $url, [ 'Accept-Encoding' => 'gzip' ]);
                $kernel->post('ua', 'request', 'parse_feed', $req);
            },
            parse_feed => sub {
                my ($kernel, $heap, $request_packet, $response_packet) = @_[KERNEL, HEAP, ARG0, ARG1];
                print "Parse_Feed called\n";

                my $req = $request_packet->[0];
                my $uri = $req->uri;
                print " for " . $uri->as_string . "\n";
                my $res = $response_packet->[0];
                my $feed_xml = $res->content;
                $feed_xml =~ s{<callbacktest:randomColor>azure</callbacktest:randomColor>}{};
                my $feed = XML::Feed->parse(\$feed_xml);

                if (!$feed) {
                    warn "Not feed\n";
                    return;
                }
                if (!$feed->{rss}) {
                    warn "Not feed.rss\n";
                    return;
                }

                my $cloud = $feed->{rss}->channel('cloud');
                if ($cloud) {
                    print "Cloud enabled feed " . Dumper($cloud);
                    $kernel->post(subscriptions => subscribe_cloud => $uri, $cloud);
                }

                my $ft = DateTime::Format::RFC3339->new();

                for my $entry ($feed->entries) {
                    $kernel->post($heap->{output_alias},
                        'insert_message', {
                            id        => $entry->id,
                            author    => scalar ($feed->author || $uri->host),
                            timestamp => $ft->format_datetime($entry->issued),
                            message   => $entry->content->body,
                            link      => $entry->link,
                            title     => $entry->title,
                            feed      => {
                                title => $feed->title,
                                link  => $feed->link,
                            }
                        });
                }
                $kernel->post($heap->{output_alias}, 'update');
                $kernel->post(subscriptions => feed_updated => $uri);
            },

            post_message => sub {
                my ($kernel, $heap, $post) = @_[KERNEL,HEAP,ARG0,ARG1];

                my $self_url = $self->{options}{self_url};
                my $username = $self->{options}{post_username};
                my $password = $self->{options}{post_password};

                if (!$self_url || !$username || !$password) {
                    return;
                }

                print "Post message: " . Dumper($post);

                my $req = HTTP::Request->new(POST => $self_url, [
                    'Accept-Encoding' => 'gzip',
                    'Authorization'   => 'Basic ' . encode_base64($username.':'.$password),
                ]);

                $req->content_type('application/x-www-form-urlencoded');
                $req->content('text='.uri_escape($post->{description}).'&title='.uri_escape($post->{title}).'&link='.uri_escape($post->{link}));
                $kernel->post('ua', 'request', 'message_received', $req);
            },

            subscribe_cloud => sub {
                my ($kernel, $heap, $url, $cloud) = @_[KERNEL,HEAP,ARG0,ARG1];
                # Subscribing every 24 hours is enough

                if ($cloud->{protocol} ne 'http-post') {
                    print "Cloud protocol: ", $cloud->{protocol}, ' not supported for url ', $url, "\n";
                    return;
                }

                my $new_url = URI->new('', 'http');
                $new_url->scheme('http');
                $new_url->host($cloud->{domain});
                $new_url->port($cloud->{port});
                $new_url->path($cloud->{path});

                my $content;
                $content .= 'notifyProcedure=';
                $content .= '&port=5337';
                $content .= '&path=/notify';
                $content .= '&protocol=http-post';
                $content .= '&url1='.uri_escape($url);

                my $req = HTTP::Request->new(POST => $new_url);
                $req->content_type('application/x-www-form-urlencoded');
                $req->content($content);

                $kernel->post(ua => request => feed_subscribed => $req => $url);
            },
            feed_subscribed => sub {
                my ($kernel, $heap, $request_packet, $response_packet) = @_[KERNEL, HEAP, ARG0, ARG1];

                my $req = $request_packet->[0];
                my $tag = $request_packet->[1];
                my $uri = $req->uri;

                my $res = $response_packet->[0];
                print $res->content;

                $kernel->post(subscriptions => feed_subscribed => $tag);
                return;
            },
        }
    );
}

1;
