package WWW::Authentik::Error;

# ABSTRACT: Exception base class for WWW::Authentik

use Moo;

# No namespace::autoclean here: it would remove the overload stub.
use overload '""' => sub { $_[0]->message }, fallback => 1;

our $VERSION = '0.002';

=synopsis

    use Scalar::Util qw( blessed );

    my $user = eval { $api->get_user($pk) };
    if ( blessed $@ && $@->isa('WWW::Authentik::Error::API') && $@->is_not_found ) { ... }

=description

Every error WWW::Authentik raises is an object of one of three subclasses:
L<WWW::Authentik::Error::Validation> for wrong arguments,
L<WWW::Authentik::Error::Network> when no HTTP answer arrived, and
L<WWW::Authentik::Error::API> when authentik answered with an error. All of
them stringify to their message, so plain C<$@> matching keeps working.

=cut

has message => (
  is       => 'ro',
  required => 1
);

=attr message

The human-readable description. The object stringifies to it. It never
carries the API token, a client secret or a password.

=cut

sub throw {
  my ( $class, %arg ) = @_;
  die $class->new(%arg);
}

=method throw

    WWW::Authentik::Error::Validation->throw( message => 'base_url is required' );

Builds the exception and dies with it.

=cut

1;
