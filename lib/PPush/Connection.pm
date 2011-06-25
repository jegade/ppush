package PPush::Connection;

use strict;
use warnings;

use AnyEvent;
use JSON   ();
use Encode ();
use Try::Tiny;

use PPush::Pool;

use constant DEBUG => $ENV{PPUSH_CONNECTION_DEBUG};

sub new {
    my $class = shift;

    my $self = {@_};
    bless $self, $class;

    $self->{connect_timeout}   ||= 15;
    $self->{reconnect_timeout} ||= 15;

    $self->{on_connect_failed}   ||= sub { };
    $self->{on_connect}          ||= sub { };
    $self->{on_reconnect}        ||= sub { };
    $self->{on_reconnect_failed} ||= sub { };
    $self->{on_message}          ||= sub { };
    $self->{on_disconnect}       ||= sub { };
    $self->{on_error}            ||= sub { };

    DEBUG && warn "Connection created\n";

    return $self;
}

sub is_connected { $_[0]->{is_connected} }

sub connecting {
    my $self = shift;

    DEBUG && warn "State 'connecting'\n";

    $self->{connect_timer} = AnyEvent->timer(
        after => $self->{connect_timeout},
        cb    => sub {
            DEBUG && warn "Timeout 'connect_timeout'";

            $self->on('connect_failed')->($self);
        }
    );
}

sub reconnecting {
    my $self = shift;

    DEBUG && warn "State 'reconnecting'\n";

    $self->{reconnect_timer} = AnyEvent->timer(
        after => $self->{reconnect_timeout},
        cb    => sub {
            DEBUG && warn "Timeout 'reconnect_timeout'\n";

            $self->on('reconnect_failed')->($self);
        }
    );
}

sub connected {
    my $self = shift;

    DEBUG && warn "State 'connected'\n";

    delete $self->{connect_timer};

    $self->{is_connected} = 1;

    $self->on('connect')->($self);

    return $self;
}

sub reconnected {
    my $self = shift;

    DEBUG && warn "State 'reconnected'\n";

    delete $self->{reconnect_timer};

    $self->on('reconnect')->($self);

    return $self;
}

sub disconnected {
    my $self = shift;

    DEBUG && warn "State 'disconnected'\n";

    delete $self->{connect_timer};
    delete $self->{reconnect_timer};

    $self->{is_connected} = 0;

    $self->{disconnect_timer} = AnyEvent->timer(
        after => 0,
        cb    => sub {
            $self->on('disconnect')->($self);
        }
    );

    return $self;
}

=head2 id

    get or generate and return the connection ID

=cut

sub id {

    my $self = shift;
    $self->{id} ||= $self->_generate_id;
    return $self->{id};
}

=head2 on_*

    Related event handler

=cut

sub on_message    { shift->on( message    => @_ ) }
sub on_disconnect { shift->on( disconnect => @_ ) }
sub on_error      { shift->on( error      => @_ ) }
sub on_write      { shift->on( write      => @_ ) }

sub on {

    my $self  = shift;
    my $event = shift;

    my $name = "on_$event";

    unless (@_) {
        DEBUG && warn "Event 'on_$event'\n";

        return $self->{$name};
    }

    $self->{$name} = $_[0];

    return $self;
}

sub read {

    my $self = shift;
    my ($data) = @_;

    return $self unless defined $data;
    my $datade = Encode::decode( 'UTF-8', $data );
    my $message = JSON::decode_json( Encode::encode( 'UTF-8', $datade ) );
    $self->on('message')->( $self, $message->{header}, $message->{data} );
    return $self;
}

=head2 send_heartbeat

=cut

sub send_heartbeat {
    my $self = shift;

    $self->{heartbeat}++;

    return $self->send_message( 'heartbeat', { heartbeat => $self->{heartbeat} } );
}

=head2 send_message

=cut

sub send_message {

    my ( $self, $event, $message ) = @_;

    my $pack = $self->build_message( $event, $message );

    if ( $self->on_write ) {

        $self->on('write')->( $self, $pack );

    } else {

        warn "Could not write, why?";
    }

    return $self;
}

=head2 send_broadcast

    Broadcast a message to every connected client

=cut

sub send_broadcast {
    my $self = shift;

    my ( $event, $message ) = @_;

    foreach my $conn ( PPush::Pool->connections ) {
        next if $conn->id eq $self->id;
        next unless $conn->is_connected;

        $conn->send_message( $event, $message );
    }

    return $self;
}

=head2 send_init_message

=cut

sub send_init_message {

    my $self = shift;
    $self->send_message( 'init', {} );
    return $self;
}

=head2 build_message

    Pack the Message with Header and Data-Part

=cut

sub build_message {

    my ( $self, $event, $data ) = @_;
    my $header = { event  => $event,  id   => $self->id };
    my $pack   = { header => $header, data => $data };
    return JSON::encode_json($pack);
}

=head2 _generate_id

    Build a Connection-ID 32 alphanumerical chars

=cut

sub _generate_id {
    my $self = shift;

    my $string = '';

    my $length = 32;

    for ( my $i = 0 ; $i < $length ; ) {
        my $j = chr( int( rand(127) ) );

        if ( $j =~ /[a-zA-Z0-9]/ ) {
            $string .= $j;
            $i++;
        }
    }

    return $string;
}

1;
__END__

=head1 NAME

PPush::Connection - Connection class

=head1 DESCRIPTION

L<PPush::Connection> is a connection class that
incapsulates all the logic for bulding and parsing Socket.IO messages.

=head1 METHODS

=head2 C<new>

=head2 C<id>

=head2 C<disconnect>

=head2 C<is_connected>

=head2 C<on>

=head2 C<on_disconnect>

=head2 C<on_error>

=head2 C<on_message>

=head2 C<send_message>

=head2 C<send_broadcast>

=head1 INTERNAL METHODS

=head2 C<connect>

=head2 C<on_write>

=head2 C<read>

=head2 C<send_id_message>


=head2 C<send_heartbeat>

=cut
