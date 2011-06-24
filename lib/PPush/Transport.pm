package PPush::Transport;

use strict;
use warnings;

use JSON   ();
use Encode ();
use Try::Tiny;
use Scalar::Util qw(weaken);

use Plack::Request;
use PPush::Handle;
use PPush::Pool;

use Protocol::WebSocket::Frame;
use Protocol::WebSocket::Handshake::Server;

sub new {
    my $class = shift;

    my $self = bless {@_}, $class;

    weaken $self->{env};
    $self->{req} = Plack::Request->new($self->{env});

    return $self;
}

sub req { shift->{req} }
sub env { shift->{req}->{env} }


sub dispatch {
    my $self = shift;
    my ($cb) = @_;

    my $fh = $self->req->env->{'psgix.io'};
    return unless $fh;

    my $hs = Protocol::WebSocket::Handshake::Server->new_from_psgi($self->req->env);
    return unless $hs->parse($fh);

    return unless $hs->is_done;

    my $handle = $self->_build_handle($fh);
    my $frame = Protocol::WebSocket::Frame->new;

    return sub {
        my $respond = shift;

        $handle->write(
            $hs->to_string => sub {
                my $handle = shift;

                my $conn = $self->add_connection(on_connect => $cb);

                my $close_cb = sub {
                    $handle->close;
                    $self->client_disconnected($conn);
                };
                $handle->on_eof($close_cb);
                $handle->on_error($close_cb);

                $handle->on_heartbeat(sub { $conn->send_heartbeat });

                $handle->on_read(
                    sub {
                        $frame->append($_[1]);

                        while (my $message = $frame->next_bytes) {
                            $conn->read($message);
                        }
                    }
                );

                $conn->on_write(
                    sub {
                        my $bytes = $self->_build_frame($_[1]);

                        $handle->write($bytes);
                    }
                );

                $self->client_connected($conn);

                $conn->send_id_message($conn->id);
            }
        );
    };
}

sub _build_frame {
    my $self = shift;
    my ($bytes) = @_;

    return Protocol::WebSocket::Frame->new($bytes)->to_bytes;
}



sub add_connection {
    my $self = shift;

    return PPush::Pool->add_connection( req => $self->{req}, @_);
}

sub remove_connection {
    my $self = shift;

    PPush::Pool->remove_connection($_[0]);

    return $self;
}

sub find_connection {
    my $self = shift;

    return PPush::Pool->find_connection(@_);
}

sub client_connected {
    my $self = shift;
    my ($conn) = @_;

    return if $conn->is_connected;

    $self->_log_client_connected($conn);

    $conn->connected;
}

sub client_disconnected {
    my $self = shift;
    my ($conn) = @_;

    $self->_log_client_disconnected($conn);

    $conn->disconnected;

    $self->remove_connection($conn);

    return $self;
}

sub _log_client_connected {
    my $self = shift;
    my ($conn) = @_;

    my $logger = $self->_get_logger;
    return unless $logger;

    $logger->(
        {   level   => 'debug',
            message => sprintf(
                "Client '%s' connected via websocket",
                $conn->id
            )
        }
    );
}

sub _log_client_disconnected {
    my $self = shift;
    my ($conn) = @_;

    my $logger = $self->_get_logger;
    return unless $logger;

    $logger->(
        {   level   => 'debug',
            message => sprintf("Client '%s' disconnected", $conn->id)
        }
    );
}

sub _get_logger {
    my $self = shift;

    return $self->env->{'psgix.logger'};
}

sub _build_handle {
    my $self = shift;

    return PPush::Handle->new(@_);
}

1;
__END__

=head1 NAME

PPush::Base - Base class for transports

=head1 DESCRIPTION

L<PPush::Base> is a base class for the transports.

=head1 METHODS

=head2 C<new>

=head2 C<env>

=head2 C<req>

=head2 C<add_connection>

=head2 C<remove_connection>

=head2 C<find_connection>

=head2 C<client_connected>

=head2 C<client_disconnected>

=cut
