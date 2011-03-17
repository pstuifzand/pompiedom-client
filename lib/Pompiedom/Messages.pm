package Pompiedom::Messages;
use 5.10.0;
use strict;
use warnings;

use Template;

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
        print "Added new message:\n";
        print "  " . ($message->{title} || $message->{link}) . "\n";

        $message->{new} = 1;
        $uniques{$message->{id}} = 1;
    }

    return;
}

sub update {
    my ($self, $webkit_view, $url) = @_;

    @global_messages = sort {$b->{timestamp} <=> $a->{timestamp}} @global_messages;

    my $template = Template->new();

    my $html = '';

    $template->process('feed.tt', {
            human_readable => sub {
                my $dt = $_[0];
                if (!$dt) {
                    return;
                }
                
                $dt->set_time_zone('Europe/Amsterdam');
                return $dt->ymd . ' ' . $dt->hms;
            },
            messages => \@global_messages,
    }, \$html) or die $template->error;

    $webkit_view->load_string($html, "text/html", "UTF-8", "http://peterstuifzand.com/");

    for (@global_messages) {
        delete $_->{new};
    }

    return;
}

1;
