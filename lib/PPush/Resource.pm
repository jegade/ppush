package PPush::Resource;

use strict;
use warnings;

use PPush::Transport::Htmlfile;
use PPush::Transport::JSONPPolling;
use PPush::Transport::WebSocket;
use PPush::Transport::XHRMultipart;
use PPush::Transport::XHRPolling;

use constant DEBUG => $ENV{POCKETIO_RESOURCE_DEBUG};

my %TRANSPORTS = (
    'xhr-multipart' => 'XHRMultipart',
    'xhr-polling'   => 'XHRPolling',
    'jsonp-polling' => 'JSONPPolling',
    'flashsocket'   => 'WebSocket',
    'websocket'     => 'WebSocket',
    'htmlfile'      => 'Htmlfile'
);

sub dispatch {
    my $self = shift;
    my ($env, $cb) = @_;

    my ($type) = $env->{PATH_INFO} =~ m{^/\d+/([^\/]+)/?};

    if ( $type ) {

        my $transport = $self->_build_transport($type, env => $env);
        return unless $transport;

        return $transport->dispatch($cb);

    } else {

        
    }
}

sub _build_transport {
    my $self = shift;
    my ($type, @args) = @_;

    return unless exists $TRANSPORTS{$type};

    my $class = "PPush::Transport::$TRANSPORTS{$type}";

    DEBUG && warn "Building $class\n";

    return $class->new(@args);
}

1;
__END__

=head1 NAME

PPush::Resource - Resource class

=head1 DESCRIPTION

L<PPush::Resource> is a transport dispatcher.

=head1 METHODS

=head2 C<dispatch>

=cut
