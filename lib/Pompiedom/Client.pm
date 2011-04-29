package Pompiedom::Client;
use strict;
use warnings;
use lib 'lib';
use 5.10.0;

use URI::QueryParam;
use URI::Escape;
 
use Gtk2 -init;
use Gtk2::WebKit;

use POE;
use POE::Session::GladeXML2;

use YAML qw/LoadFile DumpFile/;
use Data::Dumper;

use Pompiedom::Messages;

my $settings_file = $ARGV[0] || 'settings.yml';
my $settings      = LoadFile($settings_file); 

sub new {
    my ($class) = @_;

    my $self=bless {}, $class;

    my $session = POE::Session::GladeXML2->create(
        glade_object => $self,
        glade_file   => 'pompiedomclient.glade',
        glade_mainwin => 'mainwindow',

        inline_states => {
            _start          => \&ui_start,
            _stop => sub {
                print "gui stopped\n";
            },
            update_messages => \&update_messages,
            notify          => \&notify,
            insert_message  => \&insert_message,
            update          => \&update,
            on_mainwindow_delete_event => \&on_mainwindow_delete_event,
            on_send_activate => \&on_send_activate,
        },
    );
    return $self;
}

sub ui_start {
    my ($kernel, $session, $heap) = @_[KERNEL, SESSION, HEAP];

    $kernel->alias_set('pompiedom');

    $heap->{main_window} = $session->gladexml->get_widget('mainwindow');
    $heap->{main_window}->set_size_request(300, 300);
    $heap->{main_window}->resize(300,600);

    my $scrolled = $session->gladexml->get_widget('scrolledwindow2');
    my $view = Gtk2::WebKit::WebView->new();
    $scrolled->add($view);
    $view->show_all;
    $heap->{view} = $view;

    $view->load_string("<div id='anchor'></div><div id='end-anchor'></div><p>No messages received</p>", "text/html", "UTF-8", "http://peterstuifzand.com/");

    my $messages = Pompiedom::Messages->new();
    $heap->{messages} = $messages;

    $kernel->post("from_server", "ok");
}

sub insert_message {
    my ($kernel, $session, $heap, $message) = @_[KERNEL, SESSION, HEAP, ARG0];
    $heap->{messages}->insert_message($message, $heap->{view});
    return;
}
sub update {
    my ($kernel, $session, $heap) = @_[KERNEL, SESSION, HEAP];
    my $scrolled = $session->gladexml->get_widget('scrolledwindow2');
    $heap->{messages}->update($heap->{view}, $scrolled);
    return;
}

# REWRITE
sub on_mainwindow_delete_event {
    my ($kernel, $heap) = @_[KERNEL, HEAP];
    $kernel->alias_remove('pompiedom');

    $kernel->signal($kernel => 'shutdown');
    $kernel->post('HTTPd'       => 'shutdown');
    $kernel->post('ua'          => 'shutdown');
    $kernel->post('feed-reader' => 'shutdown');
#    $kernel->yield('shutdown');
}

sub on_send_activate {
    my ($kernel, $session, $heap) = @_[KERNEL, SESSION,HEAP];

    my $text_view = $session->gladexml->get_widget('message_editor');
    my $message = $text_view->get_buffer()->get('text');

    my $title = $session->gladexml->get_widget('entry_title');
    my $link  = $session->gladexml->get_widget('entry_link');

    $kernel->post('feed-reader', 'post_message', {
        description => $message,
        title       => $title->get_text(),
        link        => $link->get_text(),
    });

    $text_view->get_buffer()->set_text('');
    $title->set_text('');
    $link->set_text('');

    return;
}

1;

