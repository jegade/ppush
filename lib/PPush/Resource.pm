package PPush::Resource;

use strict;
use warnings;

use PPush::Transport;

use constant DEBUG => $ENV{PPUSH_RESOURCE_DEBUG};

sub dispatch {
    my $self = shift;
    my ($env, $cb) = @_;

    my $transport = PPush::Transport->new( env => $enc ) ;
    return unless $transport;
    return $transport->dispatch($cb);

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
