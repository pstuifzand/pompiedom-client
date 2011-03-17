package Pompiedom::Subscriptions;
use 5.10.0;
use strict;
use warnings;
use YAML 'DumpFile','LoadFile';
use Data::Dumper;

sub new {
    my ($klass) = @_;
    my $self = bless { loaded => 0, subscriptions => [] }, $klass;
    return $self;
}

sub add_url {
    my ($self, $url) = @_;
    push @{$self->{subscriptions}}, {url =>$url};
    $self->save_subscriptions();
    return;
}

sub subscriptions {
    my ($self) = @_;
    return keys %{$self->{subscriptions}};
}

sub remove_url {
    my ($self, $url) = @_;
    my @urls;
    for my $sub ($self->subscriptions) {
        if ($sub->{url} ne $url) {
            push @urls, $sub;
        }
    }
    $self->{subscriptions} = \@urls;
    return;
}

sub subscription_info {
    my ($self, $uri) = @_;
    if (ref($uri)) {
        $uri = $uri->as_string;
    }
    return $self->{subscriptions}{$uri};
}

sub need_subscribe {
    my ($self, $url) = @_;
    print "Need_subscribe? for $url";
    my $sub = $self->subscription_info($url);
    if (defined($sub->{last_subscribed})) {
        my $ret = ((time()-$sub->{last_subscribed}) > 24*60*60);
        say $ret?'yes':'no',"\n";
        return $ret;
    }
    return 1;
}

sub need_update {
    my ($self, $url) = @_;
    print "Need_update? for $url\n";

    my $sub = $self->subscription_info($url);
    print Dumper($sub);

    if (defined($sub->{last_updated})) {
        return ((time()-$sub->{last_updated}) > 30 * 60);
    }
    return 1;
}

sub feed_updated {
    my ($self, $url) = @_;
    $self->{subscriptions}{$url}{last_updated} = time();
    $self->save_subscriptions();
    return;
}

sub feed_subscribed {
    my ($self, $url) = @_;
    $self->{subscriptions}{$url}{last_subscribed} = time();
    $self->save_subscriptions();
    return;
}

sub save_subscriptions {
    my ($self) = @_;
    if ($self->{loaded}) {
        DumpFile('subscriptions.yml', $self->{subscriptions});
    }
    return;
}

sub load_subscriptions {
    my ($self) = @_;
    my $subs = LoadFile('subscriptions.yml') || {};
    if (ref($subs) eq 'ARRAY') {
        my $newsubs = {};
        for my $sub (@$subs) {
            $newsubs->{$sub->{url}} = $sub;
            delete $sub->{url};
        }
        $self->{subscriptions} = $newsubs;
    }
    else {
        $self->{subscriptions} = $subs;
    }
    $self->{loaded} = 1;
    return;
}

1;
