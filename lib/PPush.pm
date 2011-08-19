package PPush;

use strict;
use warnings;

use base 'Plack::Component';

our $VERSION = '0.00904';

use Plack::Util ();
use Plack::Util::Accessor qw(resource handler class instance method);

use PPush::Resource;

sub new {
    my $self = shift->SUPER::new(@_);

    $self->handler($self->_get_handler);

    return $self;
}

sub call {
    my $self = shift;
    my ($env) = @_;

    return PPush::Resource->dispatch($env, $self->handler)
      || [400, ['Content-Type' => 'text/plain'], ['Bad request']];
}

sub _get_handler {
    my $self = shift;

    return $self->handler if $self->handler;

    die q{Either 'handler', 'class' or 'instance' must be specified}
      unless $self->instance || $self->class;

    my $method = $self->method || 'run';

    my $instance = $self->instance
      || do { Plack::Util::load_class($self->class); $self->class->new; };

    warn "Run instance";

    return $instance->run;
}

sub DESTROY {
    
    warn "Destroy PPush";
}


1;
__END__

=head1 NAME

PPush -Websocket Pusher 

=head1 SYNOPSIS

    use Plack::Builder;

    builder {
        mount "PPush", handler => sub {
            my $self = shift;

            $self->on_message(
                sub {
                    my $self = shift;
                    my ($message) = @_;

                    ...
                }
            );

            $self->send_message({buffer => []});
        };

        $app;
    };

    # or

    builder {
        mount "PPush", class => 'MyApp::Handler', method => 'run';

        $app;
    };

=head1 DESCRIPTION

L<PPush> is a server implmentatation for websockets in Perl.


=head2 Transports

All the transports are supported.

    WebSocket
    Adobe(R) Flash(R) Socket

=head2 TLS/SSL

For TLS/SSL a secure proxy is needed. C<stunnel> or L<App::TLSMe> is
recommended.

=head1 CONFIGURATIONS

=over 4

=item resource

    mount "PPush",
        resource => 'socket.io', ...;

Specifies the path prefix under which all the requests are handled. This is done
so the rest of your application won't interfere with Socket.IO specific calls.

=item handler

    mount "PPush",
        handler => sub {
            my $socket = shift;

            $socket->on_message(sub {
                my $socket = shift;
            });

            $socket->send_message('hello');
        };

=item class or instance, method

    mount "PPush",
        class => 'MyHandler', method => 'run';

    # or

    mount "PPush",
        instance => MyHandler->new(foo => 'bar'), method => 'run';

    package MyHandler;

    sub new { ...  } # or use Moose, Boose, Goose, Doose

    sub run {
        my $self = shift;

        return sub {

            # same code as above
        }
    }

Loads C<class> using L<Plack::Util::load_class>, creates a new object or uses
a passed C<instance> and runs C<run> method expecting it to return an anonymous
subroutine.

=back

=head1 DEVELOPMENT

=head2 Repository

    http://github.com/jegade/ppush

=head1 CREDITS

Based on PocketIO from Viacheslav Tykhanovskyi, C<vti@cpan.org>.

=head1 AUTHOR

Jens Gassmannm, C<jegade@cpan.org>.

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2011, Jens Gassmann

This program is free software, you can redistribute it and/or modify it under
the terms of the Artistic License version 2.0.

=cut
